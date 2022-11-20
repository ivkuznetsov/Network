//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 17/11/2022.
//

import Foundation
import CommonUtils

public enum HTTPMethod: String {
    case get, post, put, delete
}

public protocol WithResponseType: AnyObject {
    associatedtype ResponseType
    
    func task(_ work: Work<ResponseType>, session: URLSession, request: URLRequest) -> URLSessionTask
}

public struct RequestParameters {
    
    let endpoint: String?
    let method: HTTPMethod
    let parameters: [String : Any]?
    let payload: [String : Any]?
    let headers: [String: String]
    let auth: Bool
    
    public init(endpoint: String,
                method: HTTPMethod = .get,
                paramenters: [String : Any]? = nil,
                headers: [String:String] = ["Content-Type": "application/json"],
                payload: [String : Any]? = nil,
                auth: Bool = true) {
        
        self.endpoint = endpoint
        self.method = method
        self.parameters = paramenters
        self.payload = payload
        self.headers = headers
        self.auth = auth
    }
}

open class BaseRequest {
    
    let parameters: RequestParameters
    var validateBody: BodyValidation?
    
    public init(_ parameters: RequestParameters) {
        self.parameters = parameters
    }
    
    func data() throws -> Data? {
        if let payload = parameters.payload {
            return try JSONSerialization.data(withJSONObject: payload)
        }
        return nil
    }
    
    @discardableResult
    func validate(response: URLResponse?, data: Data?, error: Error?) throws -> Any? {
        if let error = error {
            print("Fail \(String(describing: self)) with error: \(error.localizedDescription)")
            throw error
        }
        
        if let data = data {
            let responseObject = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let response = response as? HTTPURLResponse {
                try validateBody?(response, responseObject as? [String : Any])
            }
            return responseObject
        }
        return nil
    }
    
    func urlRequest(baseURL: URL) -> URLRequest {
        var url: URL = baseURL
        
        if let endpoint = parameters.endpoint {
            url = url.appendingPathComponent(endpoint)
        }
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        
        if let params = parameters.parameters {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        
        let requestUrl = urlComponents.url!
        
        var urlRequest = URLRequest(url: requestUrl)
        urlRequest.allHTTPHeaderFields = parameters.headers
        urlRequest.httpMethod = parameters.method.rawValue
        
        do {
            urlRequest.httpBody = try data()
        } catch {
            fatalError(error.localizedDescription)
        }
        return urlRequest
    }
}
