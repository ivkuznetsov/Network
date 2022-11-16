//
//  RequestWork.swift
//

import Foundation
import CommonUtils

public enum HTTPMethod: String {
    case get, post, put, delete
}

public struct Settings {
    let successCodes: Set<Int>
    let authInvalidCodes: Set<Int>
}

public protocol WithResponseType {
    associatedtype ResponseType
    
    func processResponse(_ data: Data, response: HTTPURLResponse) throws -> ResponseType
}

class RequestWork<T: BaseRequest & WithResponseType>: Work<T.ResponseType> {
    
    let request: T
    let baseURL: URL
    let session: URLSession
    let authorize: (URLRequest)->()
    let logging: Bool
    
    private var task: URLSessionTask?
    private var progressObserver: Any?
    
    init(request: T,
         baseURL: URL,
         session: URLSession,
         authorize: @escaping (URLRequest)->(),
         logging: Bool) {
        
        self.request = request
        self.baseURL = baseURL
        self.session = session
        self.authorize = authorize
        self.logging = logging
        super.init()
    }
    
    override func execute() {
        let url: URL
        if let endpoint = request.parameters.endpoint {
            url = URL(string: endpoint, relativeTo: baseURL)!
        } else {
            url = baseURL
        }
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        
        if let params = request.parameters.parameters {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        
        let requestUrl = urlComponents.url!
        
        var urlRequest = URLRequest(url: requestUrl)
        urlRequest.allHTTPHeaderFields = request.parameters.headers
        urlRequest.httpMethod = request.parameters.method.rawValue
        
        if request.parameters.auth {
            authorize(urlRequest)
        }
        
        do {
            urlRequest.httpBody = try request.data()
        } catch {
            reject(error)
            return
        }
        
        let task: URLSessionTask
        if let work = self as? RequestWork<DownloadRequest> {
            task = session.downloadTask(with: urlRequest) { [weak work] url, response, error in
                if let url = url {
                    work?.resolve(url)
                } else {
                    work?.reject(error ?? RunError.custom("Invalid response"))
                }
            }
        } else if let request = request as? UploadFileRequest {
            task = session.uploadTask(with: urlRequest, fromFile: request.fileURL) { [weak self] data, response, error in
                self?.process(data, response: response, error: error)
            }
        } else if let request = request as? UploadRequest {
            task = session.uploadTask(with: urlRequest, from: request.uploadData) { [weak self] data, response, error in
                self?.process(data, response: response, error: error)
            }
        } else {
            task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
                self?.process(data, response: response, error: error)
            }
        }
        
        self.task = task
        
        progressObserver = task.progress.observe(\.fractionCompleted, changeHandler: { [weak self] progress, _ in
            self?.progress.update(progress.fractionCompleted)
        })
        
        if logging {
            print("Sending \(request)\nparameters: \((request.parameters.parameters ?? [:]) as NSDictionary)\npayload: \((request.parameters.payload ?? [:]) as NSDictionary)")
        }
        task.resume()
    }
    
    override var debugDescription: String { "Request \(request.parameters.endpoint ?? "")" }
    
    private func process(_ data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            print("Fail \(request) with error: \(error.localizedDescription)")
            reject(error)
            return
        }
        
        guard let data = data, let response = response as? HTTPURLResponse else {
            let error = RunError.custom("Missing Response")
            print("Fail \(request) with error: \(error.localizedDescription)")
            reject(error)
            return
        }
        
        do {
            let result = try request.processResponse(data, response: response)
            if logging {
                print("Success \(request), response: \(String(describing: result))")
            }
            resolve(result)
        } catch {
            print("Fail \(request) with error: \(error.localizedDescription)")
            reject(error)
        }
    }
    
    override func cancel() {
        task?.cancel()
        super.cancel()
    }
}

