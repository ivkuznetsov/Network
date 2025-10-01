//
//  NetworkProvider.swift
//

import Foundation
import CommonUtils

public struct Token: Codable, Sendable {
    public let auth: String
    public let refresh: String?
    
    public init(auth: String, refresh: String? = nil) {
        self.auth = auth
        self.refresh = refresh
    }
}

public protocol ResponsePage: Sendable {
    
    var values: [JSONDictionary] { get }
    var nextOffset: Any? { get }
    
    init?(dict: JSONDictionary)
}

public struct ResponseWithHeaders<T: Codable & Sendable>: Sendable {
    public let headers: Headers
    public let response: T
}

public typealias Headers = [String: String]

public typealias ResponseValidation = @Sendable (HTTPURLResponse, _ data: Data?, _ body: JSONDictionary?) throws -> ()

open class NetworkProvider: NSObject, URLSessionTaskDelegate {
    
    public struct Auth: Sendable {
        
        let relogin: @Sendable () async throws ->()
        let unauthCodes: [Int]
        let authorize: @Sendable (inout URLRequest, String)->()
        let refreshToken: (@Sendable (String) async throws -> Token)?
        let keychainService: String
        private let loopChecker = LoopChecker()
        
        private actor LoopChecker {
            
            let maxCount = 5
            
            var count = 0
            var latestCheckDate = Date()
            
            func checkLoop() throws {
                if latestCheckDate.timeIntervalSinceNow < 1 {
                    if count >= maxCount {
                        count = 0
                        throw RunError.custom("Authorization loop.")
                    } else {
                        count += 1
                    }
                } else {
                    count = 0
                }
                latestCheckDate = Date()
            }
        }
        
        public init(relogin: @Sendable @escaping () async throws ->(),
                    unauthCodes: [Int] = [401, 403],
                    authorize: @Sendable @escaping (inout URLRequest, String)->(),
                    refreshToken: (@Sendable (String) async throws -> Token)? = nil,
                    keychainService: String) {
            self.relogin = relogin
            self.unauthCodes = unauthCodes
            self.authorize = authorize
            self.refreshToken = refreshToken
            self.keychainService = keychainService
        }
        
        public func update(token: Token?) {
            Keychain.set(data: try? token?.toData(), service: keychainService)
        }
        
        public var token: Token? {
            if let data = Keychain.get(keychainService) {
                return try? Token.decode(data)
            }
            return nil
        }
        
        func reauth(_ error: Error, oldToken: String?) async throws {
            let currentToken = token?.auth
            if let currentToken, currentToken != oldToken { return } // already updated
            
            try await SingletonTasks.run(key: "reauth") {
                if unauthCodes.contains((error as NSError).code) {
                    if let refreshToken = refreshToken,
                       let token = token?.refresh {
                        do {
                            try await loopChecker.checkLoop()
                            update(token: try await refreshToken(token))
                        } catch {
                            try await relogin()
                        }
                    } else {
                        try await relogin()
                    }
                } else {
                    throw error
                }
            }
        }
    }
    
    public let baseURL: URL
    public let auth: Auth?
    private let validate: ResponseValidation?
    private let session: URLSession
    private let logging: Bool
    private let willSend: ((inout URLRequest)->())?
    private let willRedirect: ((URLSessionTask, HTTPURLResponse, URLRequest)->URLRequest?)?
    
    @RWAtomic private var progress: [URLRequest: (Double)->()] = [:]
    
    public init(baseURL: URL,
                auth: Auth? = nil,
                willSend: ((inout URLRequest)->())? = nil,
                willRedirect: ((URLSessionTask, HTTPURLResponse, URLRequest)->URLRequest?)? = nil,
                validate: ResponseValidation? = nil,
                session: URLSession = URLSession.shared,
                logging: Bool = true) {
        self.willRedirect = willRedirect
        self.baseURL = baseURL
        self.auth = auth
        self.validate = validate
        self.willSend = willSend
        self.session = session
        self.logging = logging
    }
    
    private func commonLoad<Result>(_ request: Request,
                                    progress: (@Sendable (Double)->())? = nil,
                                    closure: (URLRequest, Request, _ description: inout String) async throws -> Result) async throws -> Result {
        var (urlRequest, description) = try request.urlRequest(baseURL: baseURL)
        
        if let auth {
            switch request.authentication {
            case .customToken(let token): auth.authorize(&urlRequest, token)
            case .use:
                if let token = auth.token?.auth {
                    auth.authorize(&urlRequest, token)
                }
            case .skip: break
            }
        }
        
        willSend?(&urlRequest)
        
        if let progress = progress {
            _progress.mutate { $0[urlRequest] = progress }
        }
        
        let descriptionHeader = "\(UUID().uuidString.prefix(5)) \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString ?? "")"
        
        if logging {
            print("Sending:\n\(descriptionHeader)\n\(description)")
        }
        
        var responseDescription = ""
        
        do {
            let result = try await closure(urlRequest, request, &responseDescription)
            
            _progress.mutate { $0[urlRequest] = nil }
            
            if logging == true {
                print("Success:\n\(descriptionHeader)\nresponse:\n\(responseDescription)")
            }
            return result
        } catch {
            _progress.mutate { $0[urlRequest] = nil }
            
            if logging == true {
                print("Failed:\n\(descriptionHeader)\nerror:\n\(error.localizedDescription)\nresponse:\n\(responseDescription)")
            }
            if case .use = request.authentication, let auth {
                try await auth.reauth(error, oldToken: auth.token?.auth)
                return try await commonLoad(request, progress: progress, closure: closure)
            } else {
                throw error
            }
        }
    }
    
    struct ResultWithDescription<Result> {
        let value: Result
        let description: String?
    }
    
    private func dataLoad<Result>(_ request: Request,
                                  progress: (@Sendable (Double)->())? = nil,
                                  process: @Sendable (Data, URLResponse, _ description: inout String) async throws -> Result) async throws -> Result {
        
        try await commonLoad(request, progress: progress) { urlRequest, request, description in
            let (data, response) = switch request.payload {
            case .uploadFile(let source):
                switch source {
                case .fileUrl(let url): try await session.upload(for: urlRequest, fromFile: url, delegate: self)
                case .data(let data): try await session.upload(for: urlRequest, from: data, delegate: self)
                }
            default: try await session.data(for: urlRequest, delegate: self)
            }
            return try await process(data, response, &description)
        }
    }
    
    private func validate(_ response: URLResponse, dict: JSONDictionary? = nil, data: Data? = nil, description: inout String) throws {
        var dict = dict
        
        if dict == nil, let data {
            dict = try? JSONDecoder().decode(JSONDictionary.self, from: data)
        }
        description = "\(dict?.store as? NSDictionary ?? [:])"
        
        if let response = response as? HTTPURLResponse, let validate {
            try validate(response, data, dict)
        }
    }
    
    @discardableResult
    open func send(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> Headers {
        try await dataLoad(request, progress: progress) {
            try validate($1, data: $0, description: &$2)
            return ($1 as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
        }
    }
    
    open func load(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> String {
        try await dataLoad(request, progress: progress) {
            try validate($1, data: $0, description: &$2)
            
            guard let string = String(data: $0, encoding: .utf8) else {
                throw NetworkKitError.custom("Invalid response")
            }
            return string
        }
    }
    
    open func load<Result: Codable & Sendable>(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> ResponseWithHeaders<Result> {
        try await dataLoad(request, progress: progress) {
            let result = DecodedValue<Result>(data: $0)
            try validate($1, dict: try? result.value() as? JSONDictionary, data: $0, description: &$2)
            
            let responseHeaders = ($1 as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
            return try ResponseWithHeaders(headers: responseHeaders, response: result.value())
        }
    }
        
    open func load<Result: Codable & Sendable>(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> Result {
        let result: ResponseWithHeaders<Result> = try await load(request, progress: progress)
        return result.response
    }
    
    open func load<Result: ResponsePage>(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> Result {
        try await dataLoad(request, progress: progress) {
            let result = DecodedValue<JSONDictionary>(data: $0)
            try validate($1, dict: try? result.value(), data: $0, description: &$2)
            
            guard let page = Result(dict: try result.value()) else {
                throw NetworkKitError.custom("Cannot parse page")
            }
            return page
        }
    }
    
    open func download(_ request: Request, progress: (@Sendable (Double)->())? = nil) async throws -> URL {
        try await commonLoad(request, progress: progress) { urlRequest, request, description -> URL in
            let (url, response) = try await session.download(for: urlRequest, delegate: self)
            try validate(response, description: &description)
            return url
        }
    }
    
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        guard let reqeust = task.currentRequest, let progress = self.progress[reqeust] else { return }
        
        task.progress.observe(\.fractionCompleted) { item, _ in
            DispatchQueue.main.async { progress(item.fractionCompleted) }
        }.retained(by: task)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        if let willRedirect {
            return willRedirect(task, response, request)
        }
        return request
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if task.originalRequest?.httpBodyStream != nil {
            task.progress.totalUnitCount = totalBytesExpectedToSend
            task.progress.completedUnitCount = totalBytesSent
        }
    }
}

fileprivate enum DecodedValue<V: Codable> {
    case value(V)
    case error(Error)
    
    func value() throws -> V {
        switch self {
        case .value(let value): return value
        case .error(let error): throw error
        }
    }
    
    init(data: Data) {
        do {
            self = .value(try JSONDecoder().decode(V.self, from: data))
        } catch {
            self = .error(error)
        }
    }
}
