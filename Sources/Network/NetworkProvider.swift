//
//  NetworkProvider.swift
//

import Foundation
import CommonUtils

public struct Token: Codable {
    let auth: String
    let refresh: String?
    
    public init(auth: String, refresh: String? = nil) {
        self.auth = auth
        self.refresh = refresh
    }
}

public typealias ResponseValidation = (HTTPURLResponse, _ body: [String : Any]?) throws -> ()

open class NetworkProvider: NSObject, URLSessionTaskDelegate {
    
    public struct AuthRefresher {
        
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
        
        func update(token: Token?) {
            Keychain.set(data: try? token?.toData(), service: keychainService)
        }
        
        var token: Token? {
            if let data = Keychain.get(keychainService) {
                return try? Token.decode(data)
            }
            return nil
        }
        
        func reauth(_ error: Error, oldToken: String?) async throws {
            let currentToken = token?.auth
            if let currentToken = currentToken, currentToken != oldToken { return } // already updated
            
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
    private let auth: AuthRefresher?
    private let validateBody: ResponseValidation?
    private let session: URLSession
    private let logging: Bool
    private let willSend: ((inout URLRequest)->())?
    
    public init(baseURL: URL,
                auth: AuthRefresher? = nil,
                willSend: ((inout URLRequest)->())? = nil,
                validateBody: ResponseValidation? = nil,
                session: URLSession = URLSession.shared,
                logging: Bool = true) {
        self.baseURL = baseURL
        self.auth = auth
        self.validateBody = validateBody
        self.willSend = willSend
        self.session = session
        self.logging = logging
    }
    
    open func load<T: BaseRequest & WithResponseType>(_ request: T, customToken: String? = nil) async throws -> T.ResponseType {
        
        request.validateBody = validateBody
        
        var urlRequest = request.urlRequest(baseURL: baseURL)
        let token = request.parameters.auth ? (customToken ?? auth?.token?.auth) : nil
        
        if let token = token {
            auth?.authorize(&urlRequest, token)
        }
        willSend?(&urlRequest)
        
        if logging {
            print("Sending \(urlRequest.url?.absoluteString ?? "")\nparameters: \((request.parameters.parameters ?? [:]) as NSDictionary)\npayload: \((request.parameters.payload ?? [:]) as NSDictionary)")
        }
        
        do {
            let result = try await request.load(session: session, request: urlRequest, delegate: self)
            
            if logging == true {
                print("Success \(request.parameters.endpoint ?? ""), response: \(String(describing: result))")
            }
            return result
        } catch {
            if logging == true {
                print("Failed \(request.parameters.endpoint ?? ""), error: \(error.localizedDescription)")
            }
            if customToken == nil, let auth = auth {
                try await auth.reauth(error, oldToken: token)
                return try await load(request)
            } else {
                throw error
            }
        }
    }
}
