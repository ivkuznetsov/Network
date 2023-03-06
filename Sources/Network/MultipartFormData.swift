//
//  File.swift
//  
//
//  Created by Ilya Kuznetsov on 06/03/2023.
//

import Foundation

struct MultipartFormData {
    
    let boundary: String = UUID().uuidString
    private var formData = Data()

    var httpBody: Data {
        var data = formData
        data.append("--\(boundary)--")
        return data
    }

    mutating func addField(named name: String, value: String) {
        formData.addField("--\(boundary)")
        formData.addField("Content-Disposition: form-data; name=\"\(name)\"")
        formData.addField("Content-Type: text/plain; charset=ISO-8859-1")
        formData.addField("Content-Transfer-Encoding: 8bit")
        formData.addField(value)
    }

    mutating func addField(named name: String, filename: String, data: Data) {
        formData.addField("--\(boundary)")
        formData.addField("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"")
        formData.addField(data)
    }
}

fileprivate extension Data {
    
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }

    mutating func addField(_ string: String) {
        append(string)
        append(.httpFieldDelimiter)
    }

    mutating func addField(_ data: Data) {
        append(data)
        append(.httpFieldDelimiter)
    }
}

fileprivate extension String {
    static let httpFieldDelimiter = "\r\n"
}
