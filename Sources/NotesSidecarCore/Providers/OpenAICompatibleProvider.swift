import Foundation

/// OpenAI 兼容流式 chat/completions 客户端。MVP 不假设响应里有 reasoning 字段；只关心 token + text delta。
public actor OpenAICompatibleProvider: ModelProvider {
    public nonisolated let capabilities: ProviderCapabilities = [.streaming, .tools, .jsonMode]

    private let profile: ProviderProfile
    private let session: URLSession
    private let redactor = Redactor.shared

    public init(profile: ProviderProfile) {
        self.profile = profile
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = profile.requestTimeout
        cfg.timeoutIntervalForResource = max(profile.requestTimeout * 2, profile.requestTimeout + 30)
        self.session = URLSession(configuration: cfg)
    }

    public nonisolated func testConnection() async throws {
        var req = URLRequest(url: makeURL(path: "/models") ?? URL(fileURLWithPath: "/"))
        req.httpMethod = "GET"
        await applyCommonHeaders(&req)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError.networkFailure("non-http") }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.serverError(http.statusCode, ProviderResponseDetail.message(from: data))
        }
    }

    public nonisolated func stream(_ request: ModelRequest, messages: [ModelMessage], systemPrompt: String) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var msgs: [[String: String]] = []
                    if !systemPrompt.isEmpty { msgs.append(["role": "system", "content": systemPrompt]) }
                    msgs.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
                    let body = OpenAICompatibleRequestPayload.make(
                        request: request,
                        messages: msgs,
                        profile: profile
                    )
                    let json = try JSONSerialization.data(withJSONObject: body)

                    var req = URLRequest(url: makeURL(path: "/chat/completions") ?? URL(fileURLWithPath: "/"))
                    req.httpMethod = "POST"
                    await applyCommonHeaders(&req)
                    req.httpBody = json
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    continuation.yield(.started(Date()))
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw ProviderError.networkFailure("non-http") }
                    if !(200..<300).contains(http.statusCode) {
                        throw ProviderError.serverError(http.statusCode, await ProviderResponseDetail.message(from: bytes))
                    }

                    var parser = SSEParser()
                    var inputTokens: Int? = nil
                    var outputTokens: Int? = nil
                    var receivedVisibleText = false
                    for try await line in bytes.lines {
                        let normalized = line.trimmingCharacters(in: .newlines)
                        let events: [String]
                        if normalized.hasPrefix("data:") {
                            var payload = String(normalized.dropFirst(5))
                            if payload.first == " " { payload.removeFirst() }
                            events = payload.isEmpty ? [] : [payload]
                        } else {
                            events = parser.feed(normalized)
                        }
                        for ev in events {
                            guard ev == "[DONE]" || !ev.isEmpty else { continue }
                            if ev == "[DONE]" {
                                guard receivedVisibleText else {
                                    throw ProviderError.decodingFailed("服务商返回成功，但没有可显示的回答文本")
                                }
                                continuation.yield(.finished(Date(), TokenUsage(input: inputTokens, output: outputTokens)))
                                continuation.finish()
                                return
                            }
                            if let data = ev.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                if let detail = ProviderResponseDetail.errorMessageIfPresent(from: data) {
                                    throw ProviderError.serverError(http.statusCode, detail)
                                }
                                if let choices = obj["choices"] as? [[String: Any]],
                                   let first = choices.first,
                                   let delta = first["delta"] as? [String: Any],
                                   let content = delta["content"] as? String, !content.isEmpty {
                                    receivedVisibleText = true
                                    continuation.yield(.token(content))
                                }
                                if let usage = obj["usage"] as? [String: Any] {
                                    inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                                    outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
                                }
                            }
                        }
                    }
                    // Some compatible gateways close the connection without a final blank SSE line.
                    // Flush that final buffered event before deciding the response was empty.
                    for ev in parser.finish() where ev != "[DONE]" && !ev.isEmpty {
                        guard let data = ev.data(using: .utf8) else { continue }
                        if let detail = ProviderResponseDetail.errorMessageIfPresent(from: data) {
                            throw ProviderError.serverError(http.statusCode, detail)
                        }
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = obj["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            receivedVisibleText = true
                            continuation.yield(.token(content))
                        }
                    }
                    guard receivedVisibleText else {
                        throw ProviderError.decodingFailed("服务商返回成功，但没有可显示的回答文本")
                    }
                    continuation.yield(.finished(Date(), TokenUsage(input: inputTokens, output: outputTokens)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated func makeURL(path: String) -> URL? {
        let base = profile.baseURL.hasSuffix("/") ? String(profile.baseURL.dropLast()) : profile.baseURL
        return URL(string: base + path)
    }

    private nonisolated func applyCommonHeaders(_ req: inout URLRequest) async {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in profile.customHeaders where Self.isAllowedCustomHeader(name) {
            req.setValue(value, forHTTPHeaderField: name)
        }
        do {
            if let key = try await KeychainStore.shared.readString(ref: profile.keychainCredentialRef), !key.isEmpty {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        } catch {
            // Keychain 读取失败视作无 Key
        }
    }

    private nonisolated static func isAllowedCustomHeader(_ name: String) -> Bool {
        let blocked = ["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"]
        return !blocked.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// Shared request-body construction kept outside the actor so provider-specific
/// compatibility rules can be regression-tested without making a network call.
enum OpenAICompatibleRequestPayload {
    static func make(
        request: ModelRequest,
        messages: [[String: String]],
        profile: ProviderProfile
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "temperature": temperature(for: request, profile: profile),
            "messages": messages
        ]
        if let max = request.maxOutputTokens { body["max_tokens"] = max }
        // o-series 与 reasoning 模型用 reasoning_effort；其它服务商也能兼容这个 key
        if let effort = request.reasoningEffort {
            body["reasoning_effort"] = effort.openAIValue
        }
        return body
    }

    /// Kimi K2 endpoints reject every temperature except exactly 1.0.  Apply
    /// the vendor constraint at the request seam rather than asking users to
    /// discover it from a server-side 400 error.
    private static func temperature(for request: ModelRequest, profile: ProviderProfile) -> Double {
        let isKimi = profile.preset == ProviderPreset.moonshot.rawValue
            || profile.preset == ProviderPreset.kimiGlobal.rawValue
        let isKimiK2 = request.model.lowercased().hasPrefix("kimi-k2")
        return isKimi && isKimiK2 ? 1.0 : request.temperature
    }
}

/// 极简 SSE 解析器（按事件：data 拼成 \n 分隔的 event payload，遇到空行触发一次 flush）。
public struct SSEParser {
    public private(set) var eventName: String = ""
    public private(set) var dataBuffer: String = ""
    public private(set) var lastData: String? = nil

    public init() {}

    /// 每行喂进来一次；返回「该触发一次的事件 data 列表」。空 data 表示心跳，可忽略。
    public mutating func feed(_ line: String) -> [String] {
        var flushed: [String] = []
        // URLSession may preserve the carriage return from CRLF-delimited SSE.
        // Treat a lone CR exactly like the protocol's required blank separator.
        let normalized = line.trimmingCharacters(in: .newlines)
        if normalized.isEmpty {
            if !dataBuffer.isEmpty {
                flushed.append(dataBuffer)
                lastData = dataBuffer
                dataBuffer.removeAll(keepingCapacity: true)
                eventName.removeAll(keepingCapacity: true)
            }
            return flushed
        }
        if normalized.hasPrefix(":") { return flushed }
        if let colon = normalized.firstIndex(of: ":") {
            let field = String(normalized[..<colon])
            var value = String(normalized[normalized.index(after: colon)...])
            if value.first == " " { value.removeFirst() }
            switch field {
            case "event":
                eventName = value
            case "data":
                if !dataBuffer.isEmpty { dataBuffer.append("\n") }
                dataBuffer.append(value)
            default:
                break
            }
        }
        return flushed
    }

    /// Flush a final event when a server closes the stream without the SSE-mandated blank line.
    public mutating func finish() -> [String] {
        guard !dataBuffer.isEmpty else { return [] }
        let value = dataBuffer
        lastData = value
        dataBuffer.removeAll(keepingCapacity: true)
        eventName.removeAll(keepingCapacity: true)
        return [value]
    }
}
