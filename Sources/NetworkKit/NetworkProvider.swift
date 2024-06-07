//
//  NetworkProvider.swift
//

import Foundation
import CommonUtils

public struct Token: Codable {
    public let auth: String
    public let refresh: String?
    
    public init(auth: String, refresh: String? = nil) {
        self.auth = auth
        self.refresh = refresh
    }
}

public typealias ResponseValidation = (HTTPURLResponse, _ data: Data?, _ body: [String : Any]?) throws -> ()

open class NetworkProvider: NSObject, URLSessionTaskDelegate {
    
    public struct Auth {
        
        let relogin: () async throws ->()
        let unauthCodes: [Int]
        let authorize: (inout URLRequest, String)->()
        let refreshToken: ((String) async throws -> Token)?
        let keychainService: String
        
        public init(relogin: @escaping () async throws ->(),
                    unauthCodes: [Int] = [401, 403],
                    authorize: @escaping (inout URLRequest, String)->(),
                    refreshToken: ((String) async throws -> Token)? = nil,
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
    
    private let baseURL: URL
    public let auth: Auth?
    private let validate: ResponseValidation?
    private let session: URLSession
    private let logging: Bool
    private let willSend: ((inout URLRequest)->())?
    private let willRedirect: ((URLSessionTask, HTTPURLResponse, URLRequest)->URLRequest?)?
    
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
    
    open func load<T: BaseRequest & WithResponseType>(_ request: T, customToken: String? = nil, progress: ((Double)->())? = nil) async throws -> T.ResponseType {
        
        request.validate = validate
        
        var urlRequest = request.urlRequest(baseURL: baseURL, logging: logging)
        let token = request.parameters.auth ? (customToken ?? auth?.token?.auth) : nil
        
        if let token = token {
            auth?.authorize(&urlRequest, token)
        }
        willSend?(&urlRequest)
        
        if logging {
            print("Sending \(urlRequest.url?.absoluteString ?? "")\nparameters: \((request.parameters.parameters ?? [:]) as NSDictionary)\npayload: \((request.parameters.payload ?? [:]) as NSDictionary)\nheaders: \(urlRequest.allHTTPHeaderFields as? NSDictionary ?? [:])")
        }
        
        do {
            if let progress = progress {
                _progress.mutate { $0[urlRequest] = progress }
            }
            
            let result = try await request.load(session: session, request: urlRequest, delegate: self)
            
            _progress.mutate { $0[urlRequest] = nil }
            
            if logging == true {
                print("Success \(request.parameters.endpoint), response: \(String(describing: result))")
            }
            return result
        } catch {
            if logging == true {
                print("Failed \(request.parameters.endpoint), error: \(error.localizedDescription)")
            }
            if customToken == nil, let auth = auth, request.parameters.auth {
                try await auth.reauth(error, oldToken: token)
                return try await load(request, progress: progress)
            } else {
                throw error
            }
        }
    }
    
    @RWAtomic private var progress: [URLRequest:(Double)->()] = [:]
    
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
