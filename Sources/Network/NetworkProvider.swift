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

public class NetworkProvider {
    
    public struct AuthOptions {
        
        let unauthorized: (@escaping (Error?)->())->()
        let unauthCodes: [Int]
        let authorize: (URLRequest, String)->()
        let refreshToken: ((String)->Work<Token>)?
        let keychainService: String
        
        public init(unauthorized: @escaping (@escaping (Error?)->())->(),
                    unauthCodes: [Int] = [401, 403],
                    authorize: @escaping (URLRequest, String)->(),
                    refreshToken: ((String)->Work<Token>)? = nil,
                    keychainService: String) {
            self.unauthorized = unauthorized
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
    }
    
    private let baseURL: URL
    private let auth: AuthOptions?
    private let session: URLSession
    private let logging: Bool
    
    public init(baseURL: URL,
                auth: AuthOptions? = nil,
                session: URLSession = URLSession.shared,
                logging: Bool = true) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = session
        self.logging = logging
    }
    
    public func load<T: BaseRequest & WithResponseType>(_ request: T, customToken: String? = nil) -> Work<T.ResponseType> {
        
        RequestWork(request: request,
                    baseURL: baseURL,
                    session: session,
                    authorize: { [weak self] urlRequest in
                        if let token = customToken ?? self?.auth?.token?.auth {
                            self?.auth?.authorize(urlRequest, token)
                        }
                    },
                    logging: logging).seize { [weak self] error in
            
            if request.parameters.auth,
               let wSelf = self,
               let auth = wSelf.auth,
               customToken == nil,
               auth.unauthCodes.contains((error as NSError).code) {
                
                let reauth: VoidWork
                
                if let refreshToken = auth.refreshToken,
                   let token = auth.token?.refresh {
                    reauth = refreshToken(token).success {
                        auth.update(token: $0)
                    }.seize { _ in
                        wSelf.failedToAuth(auth)
                    }
                } else {
                    reauth = wSelf.failedToAuth(auth)
                }
                
                return reauth.singleton("RefreshToken\(auth.keychainService)").chainOrCancel {
                    self?.load(request)
                }
            }
            throw error
        }
    }
    
    private func failedToAuth(_ auth: AuthOptions) -> VoidWork {
        AsyncWork { work in
            DispatchQueue.main.async {
                auth.unauthorized({ error in
                    if let error = error {
                        work.reject(error)
                    } else {
                        work.resolve(())
                    }
                })
            }
        }
    }
}
