//
//  BaseRequests.swift
//

import Foundation
import CommonUtils

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

public class BaseRequest {
    
    let parameters: RequestParameters
    
    public init(_ parameters: RequestParameters) {
        self.parameters = parameters
    }
    
    func data() throws -> Data? {
        if let payload = parameters.payload {
            return try JSONSerialization.data(withJSONObject: payload)
        }
        return nil
    }
}

public class SimpleRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = Void
    
    public func processResponse(_ data: Data, response: HTTPURLResponse) throws { }
}

public class UploadRequest: SimpleRequest {
    
    let uploadData: Data
    
    public init(data: Data, parameters: RequestParameters) {
        uploadData = data
        super.init(parameters)
    }
}

public class UploadFileRequest: SimpleRequest {
    
    let fileURL: URL
    
    public init(fileURL: URL, parameters: RequestParameters) {
        self.fileURL = fileURL
        super.init(parameters)
    }
}

public class DownloadRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = URL
    
    public func processResponse(_ data: Data, response: HTTPURLResponse) throws -> URL { fatalError() }
}

public class SerializableRequest<T>: BaseRequest, WithResponseType {
    public typealias ResponseType = T
    
    public let validate: ((T, HTTPURLResponse) -> Error?)?
    
    public init(parameters: RequestParameters, validate: ((T, HTTPURLResponse) -> Error?)? = nil) {
        self.validate = validate
        super.init(parameters)
    }
    
    public func processResponse(_ data: Data, response: HTTPURLResponse) throws -> T {
        guard let result = try JSONSerialization.jsonObject(with: data, options: []) as? T else {
            throw RunError.custom("Invalid type in response")
        }
        
        if let error = validate?(result, response) {
            throw error
        }
        return result
    }
}

public protocol ResponsePage {
    
    var values: [[String : Any]] { get }
    var nextOffset: Any? { get }
    
    init?(dict: [String : Any])
}

public class PageRequest<T: ResponsePage>: SerializableRequest<T> {
    public typealias ResponseType = ResponsePage
    
    public func processResponse(_ data: Data, response: HTTPURLResponse) throws -> ResponsePage {
        guard let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any],
              let page = T(dict: result) else {
            throw RunError.custom("Invalid type in response")
        }
        
        if let error = validate?(page, response) {
            throw error
        }
        return page
    }
}
