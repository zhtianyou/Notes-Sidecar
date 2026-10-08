import Foundation

public actor OpenAIResponsesProvider: ModelProvider {
    public nonisolated let capabilities: ProviderCapabilities = [.streaming, .tools, .vision, .jsonMode, .reasoning]

    private let profile: ProviderProfile
    private let session: URLSession

    public init(profile: ProviderProfile) {
        self.profile = profile
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = profile.requestTimeout
        config.timeoutIntervalForResource = max(profile.requestTimeout * 2, profile.requestTimeout + 30)
        self.session = URLSession(configuration: config)
    }

    public func testConnection() async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(try await credential())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.networkFailure("non-http") }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.serverError(http.statusCode, ProviderResponseDetail.message(from: data))
        }
    }

    public nonisolated func stream(
        _ request: ModelRequest,
        messages: [ModelMessage],
        systemPrompt: String
    ) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await self.credential()
                    var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    var input: [[String: Any]] = [[
                        "role": "system",
                        "content": [["type": "input_text", "text": systemPrompt]],
                    ]]
                    input.append(contentsOf: messages.map { message in
                        [
                            "role": message.role,
                            "content": [["type": "input_text", "text": message.content]],
                        ]
                    })
                    var body: [String: Any] = [
                        "model": request.model,
                        "stream": true,
                        // Required for the ChatGPT plan usage route; it also
                        // avoids retaining a user conversation server-side.
                        "store": false,
                        "input": input,
                    ]
                    if let max = request.maxOutputTokens { body["max_output_tokens"] = max }
                    if let effort = request.reasoningEffort {
                        body["reasoning"] = ["effort": effort.openAIValue]
                    } else {
                        body["temperature"] = request.temperature
                    }
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
                    continuation.yield(.started(Date()))

                    let (bytes, response) = try await self.session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw ProviderError.networkFailure("non-http") }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ProviderError.serverError(http.statusCode, await ProviderResponseDetail.message(from: bytes))
                    }

                    var parser = SSEParser()
                    var usage: TokenUsage?
                    for try await line in bytes.lines {
                        for payload in parser.feed(line) {
                            if payload == "[DONE]" { continue }
                            guard let data = payload.data(using: .utf8),
                                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let type = object["type"] as? String else { continue }
                            if type == "response.output_text.delta", let delta = object["delta"] as? String {
                                continuation.yield(.token(delta))
                            } else if type == "response.completed",
                                      let response = object["response"] as? [String: Any],
                                      let rawUsage = response["usage"] as? [String: Any] {
                                usage = TokenUsage(
                                    input: rawUsage["input_tokens"] as? Int,
                                    output: rawUsage["output_tokens"] as? Int
                                )
                            } else if type == "response.failed" || type == "error" {
                                throw ProviderError.serverError(
                                    http.statusCode,
                                    ProviderResponseDetail.message(from: data)
                                )
                            }
                        }
                    }
                    for payload in parser.finish() where payload != "[DONE]" {
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let detail = ProviderResponseDetail.errorMessageIfPresent(from: data) {
                            throw ProviderError.serverError(http.statusCode, detail)
                        }
                        guard object["type"] as? String == "response.output_text.delta",
                              let delta = object["delta"] as? String else { continue }
                        continuation.yield(.token(delta))
                    }
                    continuation.yield(.finished(Date(), usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func credential() async throws -> String {
        if profile.authenticationMode == .chatGPTSubscription {
            return try await OpenAIChatGPTAuth.shared.accessToken(profile: profile)
        }
        guard let key = try await KeychainStore.shared.readString(ref: profile.keychainCredentialRef), !key.isEmpty else {
            throw ProviderError.configurationInvalid("未配置 API Key")
        }
        return key
    }
}
