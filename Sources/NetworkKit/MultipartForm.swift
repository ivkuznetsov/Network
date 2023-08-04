//
//  MultipartForm.swift
//  
//
//  Created by Ilya Kuznetsov on 06/03/2023.
//

import Foundation

struct MultipartForm: Hashable, Equatable {
    
    struct Part: Hashable, Equatable {
        let name: String
        var data: Data
        let filename: String?
        let contentType: String?
        
        var value: String? {
            get {
                return String(bytes: data, encoding: .utf8)
            }
            set {
                guard let value = newValue else {
                    data = Data()
                    return
                }
                data = value.data(using: .utf8, allowLossyConversion: true)!
            }
        }
        
        init(name: String, data: Data, filename: String? = nil, contentType: String? = nil) {
            self.name = name
            self.data = data
            self.filename = filename
            self.contentType = contentType
        }
        
        init(name: String, value: String) {
            let data = value.data(using: .utf8, allowLossyConversion: true)!
            self.init(name: name, data: data, filename: nil, contentType: nil)
        }
    }
    
    var boundary: String
    var parts: [Part]
    
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    
    public var bodyData: Data {
        var body = Data()
        
        for part in parts {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(part.name)\"")
            if let filename = part.filename?.replacingOccurrences(of: "\"", with: "_") {
                body.append("; filename=\"\(filename)\"")
            }
            body.append("\r\n")
            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\r\n")
            }
            body.append("\r\n")
            body.append(part.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        
        return body
    }
    
    public init(parts: [Part] = [], boundary: String = UUID().uuidString) {
        self.parts = parts
        self.boundary = boundary
    }
    
    public subscript(name: String) -> Part? {
        get { parts.first(where: { $0.name == name }) }
        set {
            precondition(newValue == nil || newValue?.name == name)
            
            var parts = self.parts
            parts = parts.filter { $0.name != name }
            if let newValue = newValue {
                parts.append(newValue)
            }
            self.parts = parts
        }
    }
}

extension Data {
    
    mutating func append(_ string: String) {
        append(string.data(using: .utf8, allowLossyConversion: true)!)
    }
}
