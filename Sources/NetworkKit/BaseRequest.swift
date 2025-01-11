//
//  BaseRequest.swift
//  
//
//  Created by Ilya Kuznetsov on 17/11/2022.
//

import Foundation
import CommonUtils

public enum HTTPMethod: String, Sendable {
    case get, post, put, delete, patch
}

public protocol WithResponseType {
    associatedtype ResponseType
    
    var validate: ResponseValidation? { get }
    
    func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> ResponseType
}

public struct RequestParameters: @unchecked Sendable {
    
    let endpoint: String
    let method: HTTPMethod
    let parameters: JSONDictionary?
    let payload: JSONDictionary?
    let headers: [String: String]
    let auth: Bool
    
    public init(endpoint: String,
                method: HTTPMethod = .get,
                parameters: JSONDictionary? = nil,
                headers: [String: String] = ["Content-Type": "application/json"],
                payload: JSONDictionary? = nil,
                auth: Bool = true) {
        
        self.endpoint = endpoint
        self.method = method
        self.parameters = parameters
        self.payload = payload
        self.headers = headers
        self.auth = auth
    }
}

open class BaseRequest {
    
    let parameters: RequestParameters
    public var validate: ResponseValidation?
    
    public init(_ parameters: RequestParameters) {
        self.parameters = parameters
    }
    
    func data() throws -> Data? {
        if let payload = parameters.payload {
            if parameters.headers["Content-Type"] == "application/x-www-form-urlencoded" {
                var components = URLComponents()
                components.queryItems = payload.store.map {
                    let value = $0.value.value as! String
                    return URLQueryItem(name: $0.key, value: value)
                }
                return components.query?.data(using: .utf8)
            }
            return try JSONEncoder().encode(payload)
        }
        return nil
    }
    
    func setBody(request: inout URLRequest, logging: Bool) throws {
        request.httpBody = try data()
    }
    
    func urlRequest(baseURL: URL, logging: Bool) -> URLRequest {
        var url = baseURL
        
        if parameters.endpoint.isValid {
            url = url.appendingPathComponent(parameters.endpoint)
        }
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        
        if let params = parameters.parameters {
            urlComponents.queryItems = params.store.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        
        let requestUrl = urlComponents.url!
        
        var urlRequest = URLRequest(url: requestUrl)
        urlRequest.allHTTPHeaderFields = parameters.headers
        urlRequest.httpMethod = parameters.method.rawValue.uppercased()
        
        do {
            try setBody(request: &urlRequest, logging: logging)
        } catch {
            fatalError(error.localizedDescription)
        }
        return urlRequest
    }
}
