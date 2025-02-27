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

public enum NetworkKitError: LocalizedError {
    case custom(String)
    
    public var errorDescription: String? {
        switch self {
        case .custom(let string): string
        }
    }
}

public enum DataContent: Hashable, Sendable {
    case data(Data)
    case fileUrl(URL)
}

public struct File: Hashable, Sendable {
    
    let content: DataContent
    let mimeType: String
    let fileName: String
    
    public init(content: DataContent, mimeType: String, fileName: String) {
        self.content = content
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

public typealias URLParameter = Sendable & CustomStringConvertible

public struct Request: Sendable {
    
    public enum Endpoint: Sendable {
        case relative(String)
        case absolute(URL)
    }
    
    public enum Payload: Sendable {
        case json(JSONDictionary)
        case multipart([MultipartParameter])
        case urlForm([String: String])
        case uploadFile(source: DataContent)
    }
    
    public enum Authentication: Sendable {
        case use
        case skip
        case customToken(String)
    }
    
    let endpoint: Endpoint
    let method: HTTPMethod
    var parameters: [String: URLParameter]?
    var payload: Payload?
    var headers: [String: String]
    let authentication: Authentication
    
    public init(endpoint: Endpoint,
                method: HTTPMethod = .get,
                parameters: [String: URLParameter] = [:],
                headers: [String: String] = [:],
                payload: Payload? = nil,
                authentication: Authentication = .use) {
        
        self.endpoint = endpoint
        self.method = method
        self.parameters = parameters
        self.payload = payload
        self.headers = headers
        self.authentication = authentication
    }
    
    public init(endpoint: String,
                method: HTTPMethod = .get,
                parameters: [String: URLParameter] = [:],
                headers: [String: String] = [:],
                payload: Payload? = nil,
                authentication: Authentication = .use) {
        self.init(endpoint: .relative(endpoint),
                  method: method,
                  parameters: parameters,
                  headers: headers,
                  payload: payload,
                  authentication: authentication)
    }
    
    func prepare(request: inout URLRequest, payloadDescription: inout String?) throws {
        switch payload {
        case .json(let dictionary):
            payloadDescription = "\(dictionary.store as NSDictionary)"
            request.httpBody = try JSONEncoder().encode(dictionary)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        case .multipart(let parameters):
            let form = MultipartForm(parameters: parameters)
            request.httpBodyStream = form.stream
            request.addValue("\(form.contentType)", forHTTPHeaderField: "Content-Type")
            request.addValue("\(form.contentLength)", forHTTPHeaderField: "Content-Length")
            payloadDescription = "\(form)"
        case .urlForm(let parameters):
            var components = URLComponents()
            components.queryItems = parameters.map { .init(name: $0.key, value: "\($0.value)") }
            
            if let data = components.query?.data(using: .utf8) {
                request.httpBody = data
                payloadDescription = String(data: data, encoding: .utf8)
            } else {
                throw NetworkKitError.custom("Invalid data")
            }
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        case .uploadFile(source: let url):
            payloadDescription = "fileURL: \(url)"
        case .none: break
        }
        
        var headers = request.allHTTPHeaderFields ?? [:]
        self.headers.forEach { headers[$0] = $1 }
        request.allHTTPHeaderFields = headers
        
        request.httpMethod = method.rawValue.uppercased()
    }
    
    func urlRequest(baseURL: URL) throws -> (request: URLRequest, description: String) {
        let url: URL
        
        switch endpoint {
        case .relative(let string):
            url = baseURL.appendingPathComponent(string)
        case .absolute(let absoluteURL):
            url = absoluteURL
        }
        
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw NetworkKitError.custom("Cannot make urlComponents for: \(url)")
        }
        
        if let params = parameters {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        
        guard let requestUrl = urlComponents.url else {
            throw NetworkKitError.custom("Cannot make url from components: \(urlComponents)")
        }
        
        var urlRequest = URLRequest(url: requestUrl)
        var bodyDescription: String?
        try prepare(request: &urlRequest, payloadDescription: &bodyDescription)
        
        var description = "headers: \n\((urlRequest.allHTTPHeaderFields ?? [:]) as NSDictionary)"
        if let bodyDescription {
            description += "\npayload: \n\(bodyDescription)"
        }
        return (urlRequest, description)
    }
}

@available(*, deprecated, message: "Use just Request instead.")
public typealias SerializableRequest<ResponseType> = Request

@available(*, deprecated, message: "Use just Request with multipart payload.")
public typealias MultipartUploadRequest = Request

@available(*, deprecated, message: "Use just Request instead.")
public typealias SimpleRequest = Request

@available(*, deprecated, message: "Use just Request instead with download() function of NetworkProvider")
public typealias DownloadRequest = Request
