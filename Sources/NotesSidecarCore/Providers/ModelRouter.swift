import Foundation

/// 单例路由器：把 ProviderProfile 转换成对应 ModelProvider。
/// 同时统一一次出站前的「隐私门」：只接收 SafeContext，原始内容被类型层屏蔽。
public actor ModelRouter {
    public static let shared = ModelRouter()
    private let providerFactory: @Sendable (ProviderProfile) -> any ModelProvider

    /// The default factory is used by the app. Supplying a factory keeps the
    /// privacy gate independently testable: a blocked request must never even
    /// invoke a provider (and therefore cannot create network traffic).
    public init(providerFactory: (@Sendable (ProviderProfile) -> any ModelProvider)? = nil) {
        self.providerFactory = providerFactory ?? { profile in
            if profile.preset == ProviderPreset.openai.rawValue {
                return OpenAIResponsesProvider(profile: profile)
            }
            switch profile.kind {
            case .openAICompatible: return OpenAICompatibleProvider(profile: profile)
            case .anthropic:        return AnthropicProvider(profile: profile)
            case .ollama:           return OpenAICompatibleProvider(profile: profile)
            }
        }
    }

    public func provider(for profile: ProviderProfile) -> ModelProvider {
        providerFactory(profile)
    }

    /// 出站：先经过防火墙评估，再跑 provider 流式事件；任何防火墙 hit 都阻断远端调用。
    public func egress(requestId: String,
                       safeContext: SafeContext,
                       profile: ProviderProfile,
                       systemPrompt: String,
                       onEvent: @escaping @Sendable (ModelEvent) async -> Void,
                       manifestSink: @escaping @Sendable (EgressManifest) -> Void) async throws -> TokenUsage? {

        // 1) 防火墙最终裁决
        let evaluation = await SensitiveContentFirewall.shared.evaluate(
            noteText: safeContext.noteTextSnapshot,
            userQuestion: safeContext.userQuestion,
            conversationSummary: safeContext.conversationSummary,
            imageText: safeContext.imageTextSnapshot,
            audioTranscript: safeContext.audioTranscriptSnapshot,
            requestId: requestId
        )

        if evaluation.failedClosed {
            throw ProviderError.serverError(0, SidecarLocalizer.text("隐私检查未完成（fail-closed），未发送任何远程请求", "Privacy scanning did not complete (fail closed); no remote request was sent"))
        }
        if evaluation.status.isProtected {
            // 整篇 Protected 来源被排除；如果 SafeContext 空，也直接拒绝出站
            if evaluation.status.isEmpty {
                throw ProviderError.serverError(0, SidecarLocalizer.text("整篇上下文被隐私门阻断，未发送任何远程请求", "The privacy gate blocked all context; no remote request was sent"))
            }
        }

        // 2) 出站清单
        let host = URL(string: profile.baseURL)?.host ?? profile.baseURL
        let manifest = EgressManifest(
            requestId: requestId,
            providerId: profile.id,
            targetHost: host,
            model: profile.defaultModel,
            includedSources: evaluation.status.sourceKinds,
            excludedSourceKinds: Set(SafeContext.SafeSourceKind.allCases).subtracting(evaluation.status.sourceKinds),
            safeContextHash: evaluation.status.manifestHash
        )
        manifestSink(manifest)

        // 3) 真正出站
        let model = profile.defaultModel
        let availableReasoningEfforts = profile.supportedReasoningEfforts(for: model)
        let req = ModelRequest(
            safeContext: evaluation.status,
            model: model,
            temperature: profile.temperature,
            maxOutputTokens: profile.maxOutputTokens,
            reasoningEffort: availableReasoningEfforts.contains(profile.reasoningEffort) ? profile.reasoningEffort : nil
        )
        let provider = self.provider(for: profile)
        let messages = PromptBuilder.egressMessages(from: evaluation.status)
        var lastUsage: TokenUsage? = nil
        for try await event in provider.stream(req, messages: messages, systemPrompt: systemPrompt) {
            switch event {
            case .finished(_, let usage): lastUsage = usage
            default: break
            }
            await onEvent(event)
        }
        return lastUsage
    }
}
