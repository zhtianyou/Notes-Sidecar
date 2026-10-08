import Foundation

/// 预设服务商：与 pi-coding-agent 的注册表对齐，但只保留 Notes Sidecar 实际会用到的几个。
/// 每条 preset 可以一键创建一个 ProviderProfile。模型目录不在此维护：
/// 仅在用户完成授权后从该 Provider 的实际接口读取。
public enum ProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai
    case gemini
    case deepseek
    case moonshot
    case kimiGlobal
    case zhipu
    case minimax
    case minimaxGlobal
    case ollama
    case customOpenAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic:    return "Anthropic"
        case .openai:       return "OpenAI"
        case .gemini:       return "Google Gemini"
        case .deepseek:     return "DeepSeek"
        case .moonshot:     return "Moonshot (Kimi China)"
        case .kimiGlobal:   return "Kimi (Global)"
        case .zhipu:        return "Zhipu GLM"
        case .minimax:      return "MiniMax CN"
        case .minimaxGlobal:return "MiniMax (Global)"
        case .ollama:       return "Ollama (Local)"
        case .customOpenAI: return "Custom OpenAI-Compatible"
        }
    }

    /// 供应商 logo 用的 SF Symbol 字符
    public var symbolName: String {
        switch self {
        case .anthropic:    return "sparkles"
        case .openai:       return "bolt.horizontal.circle"
        case .gemini:       return "sparkle"
        case .deepseek:     return "magnifyingglass.circle"
        case .moonshot, .kimiGlobal: return "moon.stars"
        case .zhipu:        return "globe.asia.australia"
        case .minimax, .minimaxGlobal: return "circle.hexagongrid.fill"
        case .ollama:       return "desktopcomputer"
        case .customOpenAI: return "wrench.and.screwdriver"
        }
    }

    public var kind: ProviderKind {
        switch self {
        case .anthropic, .minimax, .minimaxGlobal: return .anthropic
        case .ollama:                            return .ollama
        case .openai, .gemini, .deepseek, .moonshot, .kimiGlobal,
             .zhipu, .customOpenAI:              return .openAICompatible
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .anthropic:    return "https://api.anthropic.com"
        case .openai:       return "https://api.openai.com/v1"
        // Google's official OpenAI-compatible Gemini surface supports both
        // `GET /models` and streamed `POST /chat/completions`.
        case .gemini:       return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .deepseek:     return "https://api.deepseek.com"
        case .moonshot:     return "https://api.moonshot.cn/v1"
        case .kimiGlobal:   return "https://api.moonshot.ai/v1"
        case .zhipu:        return "https://open.bigmodel.cn/api/paas/v4"
        case .minimax:      return "https://api.minimaxi.com/anthropic"
        case .minimaxGlobal:return "https://api.minimax.io/anthropic"
        case .ollama:       return "http://127.0.0.1:11434/v1"
        case .customOpenAI: return ""
        }
    }

    public var capabilities: ProviderCapabilities {
        switch self {
        case .anthropic:
            return [.streaming, .tools, .vision, .reasoning]
        case .openai:
            return [.streaming, .tools, .vision, .jsonMode, .reasoning]
        case .gemini:
            return [.streaming, .tools, .vision, .jsonMode, .reasoning]
        case .deepseek:
            return [.streaming, .tools, .reasoning]
        case .moonshot, .kimiGlobal:
            return [.streaming, .tools]
        case .zhipu:
            return [.streaming, .tools]
        case .minimax, .minimaxGlobal:
            return [.streaming, .tools, .vision, .jsonMode, .reasoning]
        case .ollama:
            return [.streaming]
        case .customOpenAI:
            return [.streaming, .jsonMode]
        }
    }

    /// 本机模型不需要 API Key
    public var requiresAPIKey: Bool {
        kind.requiresAPIKey
    }

    /// 一键构造 Profile（不写 Key）
    public func makeProfile() -> ProviderProfile {
        ProviderProfile(
            name: displayName,
            kind: kind,
            capabilities: capabilities,
            baseURL: defaultBaseURL,
            defaultModel: "",
            preset: rawValue
        )
    }
}
