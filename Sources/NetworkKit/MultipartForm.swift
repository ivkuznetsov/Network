//
//  MultipartForm.swift
//  
//
//  Created by Ilya Kuznetsov on 06/03/2023.
//

import Foundation
import CommonUtils

struct MultipartForm: Hashable, Equatable, Sendable {
    
    let id = UUID().uuidString
    let boundary: String
    let parameters: JSONDictionary
    let fileKey: String
    let file: File
    
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    
    func makeStream(logging: Bool) -> (stream: InputStream, contentLength: Int) {
        var header = Data()
        
        var length: Int = 0
        
        parameters.store.forEach { key, item in
            header.append("--\(boundary)\r\n")
            header.append("Content-Disposition:form-data; name=\"\(key)\"\r\n")
            if let value = item.value as? String {
                header.append("\r\n")
                header.append(value)
            } else if item.value is JSONDictionary || item.value is [JSONDictionary] {
                if let value = try? JSONEncoder().encode(item) {
                    header.append("Content-Type: \"application/json\"\r\n")
                    header.append("\r\n")
                    header.append(value)
                }
            } else if let value = item.value as? NSNumber {
                header.append("\r\n")
                header.append("\(value)")
            }
            header.append("\r\n")
        }
        
        header.append("--\(boundary)\r\n")
        header.append("Content-Disposition:form-data; name=\"\(fileKey)\"; filename=\"\(file.fileName.replacingOccurrences(of: "\"", with: "_"))\"\r\n")
        header.append("Content-Type: \(file.mimeType)\r\n")
        header.append("\r\n")
        
        let headerStream = InputStream(data: header)
        length += header.count
        
        let fileStream: InputStream
        switch file.content {
        case .data(let data):
            fileStream = .init(data: data)
            length += data.count
        case .fileUrl(let url):
            fileStream = .init(url: url)!
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                length += size
            }
        }
        
        let footer = "\r\n--\(boundary)--\r\n".data(using: .utf8)!
        length += footer.count
        let footerStream = InputStream(data: footer)
        
        if logging {
            print("Body:\n\(String(data: header, encoding: .utf8)!)[file data]\(String(data: footer, encoding: .utf8)!)")
        }
        return (MultiStream(inputStreams: [headerStream, fileStream, footerStream]), length)
    }
    
    public init(fileKey: String, file: File, parameters: JSONDictionary, boundary: String = UUID().uuidString) {
        self.fileKey = fileKey
        self.parameters = parameters
        self.file = file
        self.boundary = boundary
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MultipartForm, rhs: MultipartForm) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

fileprivate extension Data {
    
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}

fileprivate final class MultiStream: InputStream {

    private var _delegate: (any StreamDelegate)?
    override var delegate: (any StreamDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    
    private var _streamError: Error?
    override var streamError: Error? { _streamError }
    
    @RWAtomic private var _streamStatus: Stream.Status = .notOpen
    override var streamStatus: Stream.Status { _streamStatus }
    
    init(inputStreams: [InputStream]) {
        self.inputStreams = inputStreams
        super.init()
    }

    private let inputStreams: [InputStream]
    @RWAtomic private var currentIndex: Int = 0

    override func open() {
        _streamStatus = .opening
        _streamStatus = .open
        inputStreams[0].open()
    }

    override func close() {
        inputStreams.forEach { $0.close() }
        _streamStatus = .closed
    }

    override var hasBytesAvailable: Bool {
        currentIndex < inputStreams.count
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) -> Int {
        if _streamStatus == .closed { return 0 }

        while currentIndex < inputStreams.count {
            let currentInputStream = inputStreams[currentIndex]
            
            if currentInputStream.streamStatus == .notOpen {
                currentInputStream.open()
            }
            
            if !currentInputStream.hasBytesAvailable {
                self.currentIndex += 1
                continue
            }
            
            let numberOfBytesRead = currentInputStream.read(buffer, maxLength: maxLength)
                
            if numberOfBytesRead == 0 {
                self.currentIndex += 1
                continue
            }
            
            if numberOfBytesRead == -1 {
                self._streamError = currentInputStream.streamError
                self._streamStatus = .error
                return -1
            }
            
            return numberOfBytesRead
        }
        return 0
    }
    
    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool { false }
    
    override func property(forKey key: Stream.PropertyKey) -> Any? { nil }

    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false
    }

    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { }

    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { }
}
