//
//  MultiStream.swift
//  NetworkKit
//
//  Created by Ilya Kuznetsov on 27/02/2025.
//

import Foundation
import CommonUtils

final class MultiStream: InputStream {

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
