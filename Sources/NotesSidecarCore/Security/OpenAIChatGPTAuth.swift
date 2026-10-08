import AppKit
import CryptoKit
import Foundation
import Network
import Security

public actor OpenAIChatGPTAuth {
    public static let shared = OpenAIChatGPTAuth()

    public struct Credential: Codable, Sendable {
        let access: String
        let refresh: String
        let expires: Date
        let clientId: String
        let scopes: [String]
    }

    private static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let resource = "https://api.openai.com/v1"
    private static let redirectURI = "http://127.0.0.1:1455/auth/callback"
    private static let directScope = "chatgpt.tokens.use.direct"
    private static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

    public func isConnected(profile: ProviderProfile) async -> Bool {
        (try? await storedCredential(profile: profile)) != nil
    }

    public func disconnect(profile: ProviderProfile) async throws {
        try await KeychainStore.shared.delete(ref: profile.oauthCredentialRef)
    }

    public func signIn(profile: ProviderProfile) async throws {
        let verifier = Self.randomURLSafe(count: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(count: 32)
        let nonce = Self.randomURLSafe(count: 32)
        let deviceId = Self.deviceId()
        let callback = OAuthLoopbackServer(expectedState: state, usesSimplifiedChinese: SidecarLocalizer.usesSimplifiedChinese)
        try await callback.start()

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: "dynamic_agent_client"),
            .init(name: "agent_name_hint", value: "Notes Sidecar"),
            .init(name: "ext_agent_host_id", value: "urn:uuid:\(deviceId.lowercased())"),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "resource", value: Self.resource),
            .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "nonce", value: nonce),
        ]
        guard let url = components.url else { throw ProviderError.invalidURL }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        let result = try await callback.waitForCallback(timeout: 300)
        let credential = try await exchange(
            form: [
                "grant_type": "authorization_code",
                "client_id": result.clientId,
                "code": result.code,
                "code_verifier": verifier,
                "redirect_uri": Self.redirectURI,
                "resource": Self.resource,
            ],
            clientId: result.clientId
        )
        let data = try JSONEncoder().encode(credential)
        try await KeychainStore.shared.save(data, ref: profile.oauthCredentialRef)
    }

    public func accessToken(profile: ProviderProfile) async throws -> String {
        guard var credential = try await storedCredential(profile: profile) else {
            throw ProviderError.configurationInvalid(SidecarLocalizer.text("尚未使用 ChatGPT 登录", "Not signed in with ChatGPT"))
        }
        if credential.expires <= Date().addingTimeInterval(180) {
            credential = try await exchange(
                form: [
                    "grant_type": "refresh_token",
                    "client_id": credential.clientId,
                    "refresh_token": credential.refresh,
                    "resource": Self.resource,
                ],
                clientId: credential.clientId
            )
            try await KeychainStore.shared.save(try JSONEncoder().encode(credential), ref: profile.oauthCredentialRef)
        }
        return credential.access
    }

    private func storedCredential(profile: ProviderProfile) async throws -> Credential? {
        guard let data = try await KeychainStore.shared.read(ref: profile.oauthCredentialRef) else { return nil }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    private func exchange(form: [String: String], clientId: String) async throws -> Credential {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.networkFailure(SidecarLocalizer.text("OpenAI OAuth 无响应", "OpenAI OAuth did not respond")) }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.serverError(http.statusCode, SidecarLocalizer.text("OpenAI OAuth 授权失败", "OpenAI OAuth authorization failed"))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String,
              let expiresIn = object["expires_in"] as? Double,
              let scope = object["scope"] as? String else {
            throw ProviderError.decodingFailed(SidecarLocalizer.text("OpenAI OAuth token 响应不完整", "OpenAI OAuth token response was incomplete"))
        }
        if form["grant_type"] == "authorization_code" {
            guard let idToken = object["id_token"] as? String, !idToken.isEmpty else {
                throw ProviderError.decodingFailed(SidecarLocalizer.text("OpenAI OAuth token 响应缺少 ID token", "OpenAI OAuth token response did not include an ID token"))
            }
        }
        let granted = scope.split(separator: " ").map(String.init)
        guard granted.contains(Self.directScope) else {
            throw ProviderError.configurationInvalid(SidecarLocalizer.text("ChatGPT 授权未允许订阅额度直连", "ChatGPT authorization does not allow direct use of subscription quota"))
        }
        return Credential(
            access: access,
            refresh: refresh,
            expires: Date().addingTimeInterval(expiresIn),
            clientId: clientId,
            scopes: granted
        )
    }

    private static func deviceId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "openAIChatGPTHostId"), UUID(uuidString: existing) != nil {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: "openAIChatGPTHostId")
        return generated
    }

    private static func randomURLSafe(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    struct Result: Sendable { let code: String; let clientId: String }

    private let expectedState: String
    private let usesSimplifiedChinese: Bool
    private let lock = NSLock()
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<Result, Error>?
    private var pendingResult: Swift.Result<Result, Error>?
    private var completed = false

    init(expectedState: String, usesSimplifiedChinese: Bool) {
        self.expectedState = expectedState
        self.usesSimplifiedChinese = usesSimplifiedChinese
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        // `NWListener(using:on:)` already supplies the listening port. Setting
        // requiredLocalEndpoint as well makes Network.framework reject the
        // listener with NWError.invalidArgument on some macOS releases.
        let listener = try NWListener(using: parameters, on: 1455)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                    listener.stateUpdateHandler = nil
                case .failed(let error):
                    continuation.resume(throwing: error)
                    listener.stateUpdateHandler = nil
                default: break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> Result {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(ProviderError.networkFailure(
                SidecarLocalizer.text("等待 ChatGPT 授权超时", "Timed out waiting for ChatGPT authorization")
            )))
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                lock.unlock()
                continuation.resume(with: pendingResult)
            } else {
                callbackContinuation = continuation
                lock.unlock()
            }
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\n").first,
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://127.0.0.1:1455\(target)") else {
                self.respond(connection, status: "400 Bad Request", message: self.localized("Invalid authorization callback", "授权回调无效"))
                return
            }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let oauthError = values["error"], !oauthError.isEmpty {
                self.respond(connection, status: "400 Bad Request", message: self.localized("ChatGPT authorization was not completed", "ChatGPT 授权未完成"))
                self.finish(.failure(ProviderError.configurationInvalid(self.localized("ChatGPT authorization failed", "ChatGPT 授权失败"))))
                return
            }
            guard url.path == "/auth/callback",
                  values["state"] == self.expectedState,
                  let code = values["code"], !code.isEmpty,
                  let clientId = values["client_id"], !clientId.isEmpty else {
                self.respond(connection, status: "400 Bad Request", message: self.localized("Authorization state validation failed", "授权状态校验失败"))
                return
            }
            self.respond(connection, status: "200 OK", message: self.localized("ChatGPT sign-in is complete. You can close this page.", "ChatGPT 登录完成，可以关闭此页面。"))
            self.finish(.success(.init(code: code, clientId: clientId)))
        }
    }

    private func respond(_ connection: NWConnection, status: String, message: String) {
        let body = "<html><body><h2>\(message)</h2></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func localized(_ english: String, _ simplifiedChinese: String) -> String {
        usesSimplifiedChinese ? simplifiedChinese : english
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = callbackContinuation
        callbackContinuation = nil
        if continuation == nil { pendingResult = result }
        lock.unlock()
        listener?.cancel()
        continuation?.resume(with: result)
    }
}
