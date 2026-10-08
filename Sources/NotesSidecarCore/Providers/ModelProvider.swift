import Foundation

/// Core and AppKit code paths do not inherit SwiftUI's locale environment.
/// This small resolver keeps user-visible runtime errors aligned with the
/// interface-language preference without making Core depend on AppModel.
public enum SidecarLocalizer {
    public static var usesSimplifiedChinese: Bool {
        let preference = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "automatic"
        if preference == "simplifiedChinese" { return true }
        if preference == "english" { return false }
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        guard let first = languages.first?.replacingOccurrences(of: "_", with: "-").lowercased() else { return false }
        guard first == "zh" || first.hasPrefix("zh-") else { return false }
        return !(first.contains("hant") || first.hasPrefix("zh-tw") || first.hasPrefix("zh-hk") || first.hasPrefix("zh-mo"))
    }

    public static func text(_ simplifiedChinese: String, _ english: String) -> String {
        usesSimplifiedChinese ? simplifiedChinese : english
    }
}

public struct ModelRequest: Sendable {
    public let safeContext: SafeContext
    public let model: String
    public let temperature: Double
    public let maxOutputTokens: Int?
    public let reasoningEffort: ReasoningEffort?
    public init(safeContext: SafeContext, model: String, temperature: Double = 0.7, maxOutputTokens: Int? = nil, reasoningEffort: ReasoningEffort? = nil) {
        self.safeContext = safeContext
        self.model = model
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.reasoningEffort = reasoningEffort
    }
}

public struct ModelMessage: Codable, Sendable, Hashable {
    public let role: String       // "system" | "user" | "assistant"
    public let content: String
    public init(role: String, content: String) {
        self.role = role; self.content = content
    }
}

public enum ModelEvent: Sendable {
    case started(Date)
    case token(String)
    case finished(Date, TokenUsage?)
}

public struct TokenUsage: Sendable, Hashable, Codable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public init(input: Int?, output: Int?) {
        self.inputTokens = input; self.outputTokens = output
    }
}

public enum ProviderError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    case networkFailure(String)
    case decodingFailed(String)
    case modelNotFound
    case serverError(Int, String)
    case configurationInvalid(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL:                 return SidecarLocalizer.text("endpoint URL 不合法", "The endpoint URL is invalid")
        case .invalidAPIKey:              return SidecarLocalizer.text("API Key 无效", "The API key is invalid")
        case .rateLimited(let r):
            return SidecarLocalizer.text(
                "请求过于频繁" + (r.map { "（\($0)s 后重试）" } ?? ""),
                "Too many requests" + (r.map { " (retry after \($0)s)" } ?? "")
            )
        case .networkFailure(let s):      return SidecarLocalizer.text("网络失败：\(s)", "Network failure: \(s)")
        case .decodingFailed(let s):      return SidecarLocalizer.text("解码失败：\(s)", "Could not decode the response: \(s)")
        case .modelNotFound:              return SidecarLocalizer.text("模型不存在", "The selected model was not found")
        case .serverError(let c, let s):  return SidecarLocalizer.text("服务端错误 \(c)：\(s)", "Server error \(c): \(s)")
        case .configurationInvalid(let s): return SidecarLocalizer.text("配置无效：\(s)", "Invalid configuration: \(s)")
        case .timeout:                    return SidecarLocalizer.text("请求超时", "The request timed out")
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .timeout, .networkFailure: return true
        case .serverError(let c, _): return c >= 500
        default: return false
        }
    }

    public var retryAfter: TimeInterval? {
        if case .rateLimited(let r) = self { return r }
        return nil
    }
}

public protocol ModelProvider: Sendable {
    nonisolated var capabilities: ProviderCapabilities { get }
    func testConnection() async throws
    func stream(_ request: ModelRequest, messages: [ModelMessage], systemPrompt: String) -> AsyncThrowingStream<ModelEvent, Error>
}

/// Extracts a concise, user-safe message from a provider's own HTTP error.
/// Providers differ in envelope shape, but commonly place their explanation in
/// `error.message`, `message`, or `detail`. We preserve that explanation while
/// redacting credential-like values and limiting it to a small UI-safe size.
public enum ProviderResponseDetail {
    public static func message(from data: Data, maxLength: Int = 500) -> String {
        guard !data.isEmpty else { return "" }
        let extracted: String
        if let object = try? JSONSerialization.jsonObject(with: data) {
            extracted = firstMessage(in: object) ?? String(decoding: data, as: UTF8.self)
        } else {
            extracted = String(decoding: data, as: UTF8.self)
        }
        return sanitize(extracted, maxLength: maxLength)
    }

    public static func message(from bytes: URLSession.AsyncBytes, maxLength: Int = 8_192) async -> String {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxLength { break }
            }
        } catch {
            return ""
        }
        return message(from: data)
    }

    /// Returns a provider-authored message only when a successful HTTP stream
    /// contains an actual error envelope. This prevents a normal streamed
    /// message or metadata event from being mistaken for an error.
    public static func errorMessageIfPresent(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              isErrorEnvelope(dictionary),
              let detail = firstMessage(in: dictionary),
              !detail.isEmpty else { return nil }
        return sanitize(detail, maxLength: 500)
    }

    private static func isErrorEnvelope(_ dictionary: [String: Any]) -> Bool {
        if dictionary["error"] != nil || dictionary["error_message"] != nil || dictionary["error_msg"] != nil {
            return true
        }
        if let type = dictionary["type"] as? String,
           ["error", "response.failed"].contains(type.lowercased()) {
            return true
        }
        // MiniMax uses `base_resp.status_code` / `status_msg`. A zero code is
        // a successful transport envelope; a nonzero code is its official
        // error result even if it arrives with an HTTP 2xx status.
        if let base = dictionary["base_resp"] as? [String: Any],
           let code = base["status_code"] as? NSNumber,
           code.intValue != 0 {
            return true
        }
        return false
    }

    private static func firstMessage(in object: Any) -> String? {
        if let string = object as? String, !string.isEmpty { return string }
        if let array = object as? [Any] {
            return array.lazy.compactMap(firstMessage(in:)).first
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        // These names cover Anthropic, OpenAI and OpenAI-compatible APIs
        // (including DeepSeek and Ollama), as well as MiniMax's
        // `base_resp.status_msg`. Prefer a provider's human-facing message
        // instead of presenting a local interpretation of its error code.
        for key in [
            "message", "detail", "error_description", "error_message",
            "status_msg", "status_message", "msg", "error_msg", "error"
        ] {
            if let value = dictionary[key], let message = firstMessage(in: value) {
                return message
            }
        }
        // Gateways sometimes nest a documented envelope in `result`,
        // `base_resp`, or another transport object. Only traverse containers
        // after the current object has no explicit explanatory field.
        return dictionary.values.lazy.compactMap { value in
            guard value is [String: Any] || value is [Any] else { return nil }
            return firstMessage(in: value)
        }.first
    }

    private static func sanitize(_ input: String, maxLength: Int) -> String {
        var value = input
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)bearer\s+[a-z0-9._\-]{8,}"#,
            #"(?i)sk(?:-ant)?-[a-z0-9_\-]{8,}"#,
            #"(?i)(?:api[_ -]?key|authorization|token)\s*[:=]\s*[\"']?[^\s,}\"']+"#
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "[redacted credential]", options: .regularExpression)
        }
        return String(value.prefix(maxLength))
    }
}
