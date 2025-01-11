//
//  BaseRequests.swift
//

import Foundation
import CommonUtils

open class SimpleRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = Void
    
    public func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> () {
        let result = try await session.data(for: request, delegate: delegate)
        try validate(response: result.1, data: result.0)
    }
}

public struct File: Hashable, Sendable {
    
    public enum Content: Hashable, Sendable {
        case data(Data)
        case fileUrl(URL)
    }
    
    let content: Content
    let mimeType: String
    let fileName: String
    
    public init(content: Content, mimeType: String, fileName: String) {
        self.content = content
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

open class MultipartUploadRequest: SimpleRequest {
    
    let multiPartForm: MultipartForm
    
    public init(file: File, fileKey: String = "file", parameters: RequestParameters) {
        multiPartForm = .init(fileKey: fileKey, file: file, parameters: parameters.payload ?? [:])
        
        var headers = parameters.headers
        headers["Content-Type"] = multiPartForm.contentType
        
        let resultParameters = RequestParameters(endpoint: parameters.endpoint,
                                                 method: .post,
                                                 parameters: parameters.parameters,
                                                 headers: headers,
                                                 payload: nil,
                                                 auth: parameters.auth)
        super.init(resultParameters)
    }
    
    override func setBody(request: inout URLRequest, logging: Bool) throws {
        let stream = multiPartForm.makeStream(logging: logging)
        request.httpBodyStream = stream.stream
        request.addValue("\(stream.contentLength)", forHTTPHeaderField: "Content-Length")
    }
}

open class UploadRequest: SimpleRequest {
    let uploadData: Data
    
    public init(data: Data, parameters: RequestParameters) {
        uploadData = data
        super.init(parameters)
    }
    
    public func load(session: URLSession, request: URLRequest) async throws -> () {
        let result = try await session.data(for: request)
        try validate(response: result.1, data: result.0)
    }
    
    public override func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> () {
        let result = try await session.upload(for: request, from: uploadData, delegate: delegate)
        try validate(response: result.1, data: result.0)
    }
}

open class UploadFileRequest: SimpleRequest {
    let fileURL: URL
    
    public init(fileURL: URL, parameters: RequestParameters) {
        self.fileURL = fileURL
        super.init(parameters)
    }
    
    public override func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> () {
        let result = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        try validate(response: result.1, data: result.0)
    }
}

open class DownloadRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = URL
    
    public func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> URL {
        let result = try await session.download(for: request, delegate: delegate)
        try validate(response: result.1, data: nil)
        return result.0
    }
}

open class SerializableRequest<T>: BaseRequest, WithResponseType {
    public typealias ResponseType = T
    
    public func convert(_ jsonObject: Any) throws -> T {
        if let result = jsonObject as? T {
            return result
        }
        throw RunError.custom("Invalid response type")
    }
    
    public func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> T {
        let result = try await session.data(for: request, delegate: delegate)
        let jsonObject = try validate(response: result.1, data: result.0)
        
        guard let jsonObject = jsonObject else {
            throw RunError.custom("No data in response")
        }
        return try convert(jsonObject)
    }
}

extension WithResponseType {
    
    @discardableResult
    func validate(response: URLResponse, data: Data?) throws -> Any? {
        var resultError: Error?
        var responseObject: Any?
        
        if let data = data, data.count > 0 {
            do {
                if let type = Self.ResponseType.self as? Codable.Type {
                    responseObject = try JSONDecoder().decode(type, from: data)
                } else {
                    responseObject = try JSONSerialization.jsonObject(with: data, options: [])
                }
            } catch {
                resultError = error
            }
        }
        
        if let response = response as? HTTPURLResponse, let validate = self.validate {
            try validate(response, data, responseObject as? [String : Any])
        }
        if let error = resultError {
            throw error
        }
        return responseObject
    }
}

public protocol ResponsePage: Sendable {
    
    var values: [[String : Any]] { get }
    var nextOffset: Any? { get }
    
    init?(dict: [String : Any])
}

open class PageRequest<T: ResponsePage>: SerializableRequest<T> {
    public typealias ResponseType = ResponsePage
    
    public override func convert(_ jsonObject: Any) throws -> T {
        if let result = jsonObject as? [String : Any],
           let page = T(dict: result) {
            return page
        }
        throw RunError.custom("Invalid response type")
    }
}
