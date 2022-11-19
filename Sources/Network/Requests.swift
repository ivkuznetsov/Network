//
//  BaseRequests.swift
//

import Foundation
import CommonUtils

public class SimpleRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = Void
    
    public func task(_ work: Work<Void>, session: URLSession, request: URLRequest) -> URLSessionTask {
        session.dataTask(with: request) { [weak self] data, response, error in
            do {
                try self?.validate(response: response, error: error)
                work.resolve(())
            } catch {
                work.reject(error)
            }
        }
    }
}

public class UploadRequest: SimpleRequest {
    
    let uploadData: Data
    
    public init(data: Data, parameters: RequestParameters) {
        uploadData = data
        super.init(parameters)
    }
    
    public override func task(_ work: Work<Void>, session: URLSession, request: URLRequest) -> URLSessionTask {
        session.uploadTask(with: request, from: uploadData) { [weak self] _, response, error in
            do {
                try self?.validate(response: response, error: error)
                work.resolve(())
            } catch {
                work.reject(error)
            }
        }
    }
}

public class UploadFileRequest: SimpleRequest {
    
    let fileURL: URL
    
    public init(fileURL: URL, parameters: RequestParameters) {
        self.fileURL = fileURL
        super.init(parameters)
    }
    
    public override func task(_ work: Work<Void>, session: URLSession, request: URLRequest) -> URLSessionTask {
        session.uploadTask(with: request, fromFile: fileURL) { [weak self] _, response, error in
            do {
                try self?.validate(response: response, error: error)
                work.resolve(())
            } catch {
                work.reject(error)
            }
        }
    }
}

public class DownloadRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = URL
    
    public func task(_ work: Work<URL>, session: URLSession, request: URLRequest) -> URLSessionTask {
        session.downloadTask(with: request) { [weak work] url, response, error in
            if let url = url {
                work?.resolve(url)
            } else {
                work?.reject(error ?? RunError.custom("Invalid response"))
            }
        }
    }
}

public class SerializableRequest<T>: BaseRequest, WithResponseType {
    public typealias ResponseType = T
    
    public let validate: ((T, HTTPURLResponse) throws -> ())?
    
    public init(parameters: RequestParameters, validate: ((T, HTTPURLResponse) throws -> ())? = nil) {
        self.validate = validate
        super.init(parameters)
    }
    
    public func convert(_ data: Data) throws -> T {
        if let result = try JSONSerialization.jsonObject(with: data, options: []) as? T {
            return result
        }
        throw RunError.custom("Invalid response type")
    }
    
    public func task(_ work: Work<T>, session: URLSession, request: URLRequest) -> URLSessionTask {
        session.dataTask(with: request) { [weak work, weak self] data, response, error in
            guard let wSelf = self else { return }
            
            do {
                let httpResponse = try wSelf.validate(response: response, error: error)
            
                guard let data = data else {
                    throw RunError.custom("No data in response")
                }
                let result = try wSelf.convert(data)
                
                try wSelf.validate?(result, httpResponse)
                
                work?.resolve(result)
            } catch {
                work?.reject(error)
            }
        }
    }
}

public protocol ResponsePage {
    
    var values: [[String : Any]] { get }
    var nextOffset: Any? { get }
    
    init?(dict: [String : Any])
}

public class PageRequest<T: ResponsePage>: SerializableRequest<T> {
    public typealias ResponseType = ResponsePage
    
    public override func convert(_ data: Data) throws -> T {
        if let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any],
           let page = T(dict: result) {
            return page
        }
        throw RunError.custom("Invalid response type")
    }
}
