import Foundation

/// Anthropic Messages API 流式客户端（messages / anthropic-version: 2023-06-01）
public actor AnthropicProvider: ModelProvider {
    public nonisolated let capabilities: ProviderCapabilities = [.streaming, .tools, .vision, .reasoning]

    private let profile: ProviderProfile
    private let session: URLSession

    public init(profile: ProviderProfile) {
        self.profile = profile
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = profile.requestTimeout
        cfg.timeoutIntervalForResource = max(profile.requestTimeout * 2, profile.requestTimeout + 30)
        self.session = URLSession(configuration: cfg)
    }

    public nonisolated func testConnection() async throws {
        guard let url = URL(string: profile.baseURL + "/v1/models") else { throw ProviderError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        await applyHeaders(&req, body: false)
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
                    let body = AnthropicRequestPayload.make(
                        request: request,
                        messages: messages,
                        systemPrompt: systemPrompt
                    )
                    let json = try JSONSerialization.data(withJSONObject: body)

                    guard let url = URL(string: profile.baseURL + "/v1/messages") else {
                        throw ProviderError.invalidURL
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    await applyHeaders(&req, body: true)
                    req.httpBody = json

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
                    var observedKinds = Set<String>()
                    var payloadCount = 0

                    func consume(_ payload: String) -> String? {
                        payloadCount += 1
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                        if let detail = ProviderResponseDetail.errorMessageIfPresent(from: data) {
                            return detail
                        }
                        let type = obj["type"] as? String ?? ""
                        let deltaType = (obj["delta"] as? [String: Any])?["type"] as? String
                        observedKinds.insert(deltaType.map { "\(type)/\($0)" } ?? (type.isEmpty ? "json" : type))
                        switch type {
                        case "content_block_start":
                            if let block = obj["content_block"] as? [String: Any],
                               block["type"] as? String == "text",
                               let text = block["text"] as? String, !text.isEmpty {
                                receivedVisibleText = true
                                continuation.yield(.token(text))
                            }
                        case "content_block_delta":
                            if let delta = obj["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String, !text.isEmpty {
                                receivedVisibleText = true
                                continuation.yield(.token(text))
                            }
                        case "message_start":
                            if let message = obj["message"] as? [String: Any],
                               let usage = message["usage"] as? [String: Any] {
                                inputTokens = usage["input_tokens"] as? Int ?? inputTokens
                            }
                        case "message_delta":
                            if let usage = obj["usage"] as? [String: Any] {
                                outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                            }
                        default:
                            // Also accept a non-streaming Anthropic Messages response.
                            if let content = obj["content"] as? [[String: Any]] {
                                for block in content where block["type"] as? String == "text" {
                                    if let text = block["text"] as? String, !text.isEmpty {
                                        receivedVisibleText = true
                                        continuation.yield(.token(text))
                                    }
                                }
                            }
                        }
                        return nil
                    }

                    for try await line in bytes.lines {
                        let normalized = line.trimmingCharacters(in: .newlines)
                        // URLSession.AsyncBytes.lines does not consistently surface the
                        // empty separator lines used by SSE. MiniMax emits one JSON object
                        // per data line, so consume those lines directly.
                        if normalized.hasPrefix("data:") {
                            var payload = String(normalized.dropFirst(5))
                            if payload.first == " " { payload.removeFirst() }
                            if !payload.isEmpty, let detail = consume(payload) {
                                throw ProviderError.serverError(http.statusCode, detail)
                            }
                        } else {
                            for event in parser.feed(normalized) {
                                if let detail = consume(event) {
                                    throw ProviderError.serverError(http.statusCode, detail)
                                }
                            }
                        }
                    }
                    for event in parser.finish() {
                        if let detail = consume(event) {
                            throw ProviderError.serverError(http.statusCode, detail)
                        }
                    }
                    guard receivedVisibleText else {
                        let kinds = observedKinds.sorted().joined(separator: ",")
                        throw ProviderError.decodingFailed(
                            "服务商返回成功，但没有可显示的回答文本（事件 \(payloadCount)：\(kinds.isEmpty ? "无" : kinds)）"
                        )
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

    private func applyHeaders(_ req: inout URLRequest, body: Bool) async {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if body { req.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        for (name, value) in profile.customHeaders where Self.isAllowedCustomHeader(name) {
            req.setValue(value, forHTTPHeaderField: name)
        }
        do {
            if let key = try await KeychainStore.shared.readString(ref: profile.keychainCredentialRef), !key.isEmpty {
                if isMiniMax {
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                } else {
                    req.setValue(key, forHTTPHeaderField: "x-api-key")
                }
            }
        } catch { /* ignore */ }
    }

    private nonisolated var isMiniMax: Bool {
        profile.preset == ProviderPreset.minimax.rawValue || profile.preset == ProviderPreset.minimaxGlobal.rawValue
    }

    private nonisolated static func isAllowedCustomHeader(_ name: String) -> Bool {
        let blocked = ["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"]
        return !blocked.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

}

/// Anthropic's current Claude 4.6+ models use adaptive thinking. Older
/// models retain the legacy budget form, but neither path sends unsupported
/// request metadata such as `thinking.display`.
enum AnthropicRequestPayload {
    static func make(request: ModelRequest,
                     messages: [ModelMessage],
                     systemPrompt: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "max_tokens": request.maxOutputTokens ?? 2048,
            "temperature": request.temperature,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }

        guard let effort = request.reasoningEffort else { return body }
        // Thinking requests must not set temperature.
        body.removeValue(forKey: "temperature")
        if usesAdaptiveThinking(model: request.model) {
            body["thinking"] = ["type": "adaptive"]
            body["output_config"] = ["effort": effort.openAIValue]
        } else {
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": legacyBudget(for: effort)
            ]
        }
        return body
    }

    private static func usesAdaptiveThinking(model: String) -> Bool {
        let identifier = model.lowercased()
        return identifier.range(
            of: #"claude-(?:opus|sonnet|haiku)-(?:[5-9]|4-(?:6|7|8))"#,
            options: .regularExpression
        ) != nil || identifier.contains("fable") || identifier.contains("mythos")
    }

    private static func legacyBudget(for effort: ReasoningEffort) -> Int {
        switch effort {
        case .low: 2_000
        case .medium: 4_000
        case .high: 8_000
        case .xhigh: 12_000
        case .max: 16_000
        }
    }
}
