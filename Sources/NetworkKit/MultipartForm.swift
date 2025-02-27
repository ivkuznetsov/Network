//
//  MultipartForm.swift
//  
//
//  Created by Ilya Kuznetsov on 06/03/2023.
//

import Foundation
import CommonUtils

public struct MultipartParameter: Sendable {
    
    public enum Content {
        case data(Data)
        case file(header: Data, content: DataContent)
    }
    
    public protocol Value: Sendable {
        func content(key: String) -> Content
    }
    
    public protocol JSONValue: Value, Codable { }
    
    let key: String
    let value: Value
    
    public init(key: String, value: Value) {
        self.key = key
        self.value = value
    }
    
    public init(file: File, fileKey: String = "file") {
        self.key = fileKey
        self.value = file
    }
}

public extension MultipartParameter.JSONValue {
    
    func content(key: String) -> MultipartParameter.Content {
        let jsonData = try! JSONEncoder().encode(self)
        var data = Data()
        data.append(key: key, mimeType: "\"application/json\"")
        data.append(jsonData)
        return .data(data)
    }
}

extension JSONDictionary: MultipartParameter.JSONValue { }

extension [JSONDictionary]: MultipartParameter.Value, MultipartParameter.JSONValue { }

extension File: MultipartParameter.Value {
    
    public func content(key: String) -> MultipartParameter.Content {
        var data = Data()
        data.append(key: key, fileName: fileName, mimeType: mimeType)
        
        switch content {
        case .data(let fileData):
            return .file(header: data, content: .data(fileData))
        case .fileUrl(let url):
            return .file(header: data, content: .fileUrl(url))
        }
    }
}

extension String: MultipartParameter.Value {
    
    public func content(key: String) -> MultipartParameter.Content {
        var data = Data()
        data.append(key: key)
        data.append(self)
        return .data(data)
    }
}

struct MultipartForm: CustomDebugStringConvertible {
    
    private let boundary: String
    let stream: InputStream
    let contentLength: Int
    let debugDescription: String
    
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    
    init(boundary: String = UUID().uuidString,
         parameters: [MultipartParameter]) {
        
        self.boundary = boundary
        var length: Int = 0
        
        var streams: [InputStream] = []
        var data = Data()
        var log = ""
        
        func commidData() {
            length += data.count
            
            if let string = String(data: data, encoding: .utf8) {
                log += string
            }
            streams.append(.init(data: data))
            data = Data()
        }
        
        parameters.forEach { parameter in
            data.append("--\(boundary)\r\n")
            
            switch parameter.value.content(key: parameter.key) {
            case .data(let parameterData):
                data.append(parameterData)
            case .file(let header, let content):
                data.append(header)
                commidData()
                
                switch content {
                case .data(let fileData):
                    data.append(fileData)
                    log += "\n [file data \(fileData.count)]"
                    commidData()
                case .fileUrl(let url):
                    streams.append(.init(url: url)!)
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    length += size
                    log += "\n [file data \(size)]"
                }
            }
            data.append("\r\n")
        }
        
        data.append("--\(boundary)--\r\n")
        commidData()
        
        stream = MultiStream(inputStreams: streams)
        contentLength = length
        debugDescription = log
    }
}

fileprivate extension Data {
    
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
    
    mutating func append(key: String, fileName: String? = nil, mimeType: String? = nil) {
        append("Content-Disposition:form-data; name=\"\(key)\"")
        
        if let fileName {
            append("; filename=\"\(fileName.replacingOccurrences(of: "\"", with: "_"))\"")
        }
        append("\r\n")
        
        if let mimeType {
            append("Content-Type: \(mimeType)\r\n")
        }
        append("\r\n")
    }
}
