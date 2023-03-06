//
//  BaseRequests.swift
//

import Foundation
import CommonUtils

open class SimpleRequest: BaseRequest, WithResponseType {
    public typealias ResponseType = Void
    
    public func load(session: URLSession, request: URLRequest, delegate: URLSessionTaskDelegate) async throws -> () {
        let result: (Data, URLResponse)
        if #available(iOS 15, *) {
            result = try await session.data(for: request, delegate: delegate)
        } else {
            result = try await session.data(for: request)
        }
        try validate(response: result.1, data: result.0)
    }
}

open class MultipartUploadRequest: UploadRequest {
    
    public struct File {
        let data: Data
        let mimeType: String
        let fileName: String
        
        public init(data: Data, mimeType: String, fileName: String) {
            self.data = data
            self.mimeType = mimeType
            self.fileName = fileName
        }
    }
    
    public init(file: File, parameters: RequestParameters) {
        var headers = parameters.headers
        
        var formData = MultipartFormData()
        parameters.payload?.forEach { key, value in
            if let value = value as? String {
                formData.addField(named: key, value: value)
            }
        }
        formData.addField(named: "Content-Type", value: file.mimeType)
        formData.addField(named: "file", filename: "file", data: file.data)
        
        headers["Content-Type"] = "multipart/form-data; boundary=\(formData.boundary)"
        
        let resultParameters = RequestParameters(endpoint: parameters.endpoint,
                                                 method: .post,
                                                 parameters: parameters.parameters,
                                                 headers: headers,
                                                 payload: nil,
                                                 auth: parameters.auth)
        
        super.init(data: formData.httpBody, parameters: resultParameters)
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
        let result: (Data, URLResponse)
        if #available(iOS 15, *) {
            result = try await session.upload(for: request, from: uploadData, delegate: delegate)
        } else {
            result = try await session.upload(for: request, from: uploadData)
        }
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
        let result: (Data, URLResponse)
        if #available(iOS 15, *) {
            result = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        } else {
            result = try await session.upload(for: request, fromFile: fileURL)
        }
        try validate(response: result.1, data: result.0)
    }
}

@available(iOS 15, *)
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
        let result: (Data, URLResponse)
        if #available(iOS 15, *) {
            result = try await session.data(for: request, delegate: delegate)
        } else {
            result = try await session.data(for: request)
        }
        let jsonObject = try validate(response: result.1, data: result.0)
        
        guard let jsonObject = jsonObject else {
            throw RunError.custom("No data in response")
        }
        return try convert(jsonObject)
    }
}

public protocol ResponsePage {
    
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
