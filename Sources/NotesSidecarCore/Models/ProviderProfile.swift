import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropic
    case ollama

    public var displayName: String {
        switch self {
        case .openAICompatible: return SidecarLocalizer.text("OpenAI 兼容", "OpenAI-Compatible")
        case .anthropic:        return "Anthropic"
        case .ollama:           return SidecarLocalizer.text("本地 Ollama", "Local Ollama")
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAICompatible: return "https://api.example.com/v1"
        case .anthropic:        return "https://api.anthropic.com"
        case .ollama:           return "http://127.0.0.1:11434"
        }
    }

    public var defaultModel: String {
        ""
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .openAICompatible, .anthropic: return true
        case .ollama: return false
        }
    }

    public var allowsInsecureHTTP: Bool {
        self == .ollama
    }
}

public enum ProviderAuthenticationMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case apiKey
    case chatGPTSubscription

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .apiKey: return "API Key"
        case .chatGPTSubscription: return SidecarLocalizer.text("ChatGPT 订阅登录", "ChatGPT Subscription")
        }
    }
}

public struct ProviderCapabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let streaming = ProviderCapabilities(rawValue: 1 << 0)
    public static let tools     = ProviderCapabilities(rawValue: 1 << 1)
    public static let vision    = ProviderCapabilities(rawValue: 1 << 2)   // 仅本地视觉 / 远程侧 P0 关闭
    public static let jsonMode  = ProviderCapabilities(rawValue: 1 << 3)
    public static let reasoning = ProviderCapabilities(rawValue: 1 << 4)

    public var label: String {
        var parts: [String] = []
        if contains(.streaming) { parts.append("Streaming") }
        if contains(.tools)     { parts.append("Tools") }
        if contains(.vision)    { parts.append("Vision") }
        if contains(.jsonMode)  { parts.append("JSON") }
        if contains(.reasoning) { parts.append("Reasoning") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case low, medium, high, xhigh, max
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .low:    return SidecarLocalizer.text("低", "Low")
        case .medium: return SidecarLocalizer.text("中", "Medium")
        case .high:   return SidecarLocalizer.text("高", "High")
        case .xhigh:  return SidecarLocalizer.text("很高", "Very High")
        case .max:    return SidecarLocalizer.text("最高", "Maximum")
        }
    }
    public var openAIValue: String { rawValue } // 用于 OpenAI o-series
}

public enum ProviderTestStatus: Codable, Hashable, Sendable {
    case unknown
    case connected(Date)
    case authFailed(String)
    case networkFailed(String)
    case rateLimited(Date)
    case unsupported(String)

    public var label: String {
        switch self {
        case .unknown: return SidecarLocalizer.text("未测试", "Not tested")
        case .connected(let d): return SidecarLocalizer.text("已连接 · \(Self.short(d))", "Connected · \(Self.short(d))")
        case .authFailed(let s): return SidecarLocalizer.text("认证失败 · \(s)", "Authentication failed · \(s)")
        case .networkFailed(let s): return SidecarLocalizer.text("网络失败 · \(s)", "Network failed · \(s)")
        case .rateLimited(let d): return SidecarLocalizer.text("限流 · \(Self.short(d))", "Rate limited · \(Self.short(d))")
        case .unsupported(let s): return SidecarLocalizer.text("不支持 · \(s)", "Unsupported · \(s)")
        }
    }

    static func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

public struct ProviderProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var defaultModel: String
    public var availableModels: [String]
    public var keychainCredentialRef: String
    public var capabilities: ProviderCapabilities
    public var lastTestStatus: ProviderTestStatus
    public var reasoningEffort: ReasoningEffort
    public var requestTimeout: Double
    public var maxOutputTokens: Int
    public var temperature: Double
    /// Non-secret headers only. Authorization, Cookie and API-key headers are
    /// deliberately rejected by the editor; credentials stay in Keychain.
    public var customHeaders: [String: String]
    public var preset: String?
    public var authenticationMode: ProviderAuthenticationMode
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String,
                kind: ProviderKind,
                capabilities: ProviderCapabilities,
                id: String = UUID().uuidString,
                baseURL: String? = nil,
                defaultModel: String? = nil,
                preset: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.defaultModel = defaultModel ?? kind.defaultModel
        self.availableModels = []
        self.keychainCredentialRef = "provider.\(id).credential"
        self.capabilities = capabilities
        self.lastTestStatus = .unknown
        self.reasoningEffort = .medium
        self.requestTimeout = 60
        self.maxOutputTokens = 4096
        self.temperature = 0.7
        self.customHeaders = [:]
        self.preset = preset
        self.authenticationMode = .apiKey
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var isLocal: Bool { kind == .ollama }
    public var oauthCredentialRef: String { "provider.\(id).chatgpt-oauth" }

    /// The editor and the request router must agree on when an effort control is
    /// meaningful. We deliberately keep this conservative: an unknown model
    /// receives no reasoning parameter instead of risking an invalid request.
    public func supportedReasoningEfforts(for model: String) -> [ReasoningEffort] {
        guard capabilities.contains(.reasoning) else { return [] }
        let identifier = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !identifier.isEmpty else { return [] }

        switch preset {
        case ProviderPreset.openai.rawValue:
            let supportsReasoning = identifier.hasPrefix("o") ||
                identifier.hasPrefix("gpt-5") ||
                identifier.hasPrefix("gpt-6") ||
                identifier.contains("codex")
            return supportsReasoning ? ReasoningEffort.allCases : []
        case ProviderPreset.deepseek.rawValue:
            return identifier.contains("reasoner") || identifier.contains("r1") || identifier.contains("thinking")
                ? ReasoningEffort.allCases : []
        case ProviderPreset.anthropic.rawValue,
             ProviderPreset.minimax.rawValue,
             ProviderPreset.minimaxGlobal.rawValue:
            return ReasoningEffort.allCases
        default:
            return []
        }
    }

    /// Apply safe, provider-specific compatibility upgrades without changing identity or credentials.
    /// This keeps profiles created by older app builds working after provider API migrations.
    public func applyingCompatibilityDefaults() -> ProviderProfile {
        if preset == ProviderPreset.openai.rawValue {
            var copy = self
            copy.capabilities.formUnion(ProviderPreset.openai.capabilities)
            // A previous generic model parser could persist response metadata
            // such as `priority` as though it were a model ID. Subscription
            // catalogs are account-specific, so clear them and re-fetch.
            if copy.authenticationMode == .chatGPTSubscription {
                copy.availableModels = []
                copy.defaultModel = ""
            }
            return copy
        }

        if preset == ProviderPreset.deepseek.rawValue {
            var copy = self
            copy.baseURL = ProviderPreset.deepseek.defaultBaseURL
            copy.capabilities.formUnion(ProviderPreset.deepseek.capabilities)
            return copy
        }

        guard preset == ProviderPreset.minimax.rawValue || preset == ProviderPreset.minimaxGlobal.rawValue else { return self }

        var copy = self
        let legacyMiniMaxURLs: Set<String> = [
            "https://api.minimax.chat/v1",
            "https://api.minimax.chat/v1/",
            "https://api.minimax.io/v1",
            "https://api.minimax.io/v1/"
        ]
        let selectedPreset = preset == ProviderPreset.minimaxGlobal.rawValue
            ? ProviderPreset.minimaxGlobal
            : ProviderPreset.minimax
        if legacyMiniMaxURLs.contains(copy.baseURL) {
            copy.baseURL = selectedPreset.defaultBaseURL
        }
        if copy.name == "MiniMax" {
            copy.name = selectedPreset.displayName
        }
        copy.kind = selectedPreset.kind
        copy.capabilities.formUnion(selectedPreset.capabilities)

        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, defaultModel, availableModels
        case keychainCredentialRef, capabilities, lastTestStatus, reasoningEffort
        case requestTimeout, maxOutputTokens, temperature, customHeaders
        case preset, authenticationMode, createdAt, updatedAt
    }

    /// 向后兼容：旧版 JSON 没 reasoningEffort 字段时默认为 .medium
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.kind = try c.decode(ProviderKind.self, forKey: .kind)
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.defaultModel = try c.decode(String.self, forKey: .defaultModel)
        self.availableModels = try c.decodeIfPresent([String].self, forKey: .availableModels) ?? []
        self.keychainCredentialRef = try c.decode(String.self, forKey: .keychainCredentialRef)
        self.capabilities = try c.decode(ProviderCapabilities.self, forKey: .capabilities)
        self.lastTestStatus = try c.decode(ProviderTestStatus.self, forKey: .lastTestStatus)
        self.reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        self.requestTimeout = try c.decodeIfPresent(Double.self, forKey: .requestTimeout) ?? 60
        self.maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 4096
        self.temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        self.customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        self.preset = try c.decodeIfPresent(String.self, forKey: .preset)
        self.authenticationMode = try c.decodeIfPresent(ProviderAuthenticationMode.self, forKey: .authenticationMode) ?? .apiKey
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
