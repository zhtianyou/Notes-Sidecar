import XCTest
@testable import NotesSidecar

final class PromptBuilderTests: XCTestCase {
    func testKeychainCredentialIsReadOnlyOncePerAppSession() async throws {
        let backend = CountingKeychainBackend(value: Data("secret".utf8))
        let store = KeychainStore(backend: backend)

        let first = try await store.readString(ref: "provider.test.credential")
        let second = try await store.readString(ref: "provider.test.credential")
        XCTAssertEqual(first, "secret")
        XCTAssertEqual(second, "secret")
        XCTAssertEqual(backend.readCount, 1)
    }

    func testMiniMaxPresetUsesBuiltInPiCompatibleEndpoints() {
        XCTAssertEqual(ProviderPreset.minimax.kind, .anthropic)
        XCTAssertEqual(ProviderPreset.minimax.defaultBaseURL, "https://api.minimaxi.com/anthropic")
        XCTAssertEqual(ProviderPreset.minimaxGlobal.defaultBaseURL, "https://api.minimax.io/anthropic")
    }

    func testMiniMaxPresetExposesReasoningControls() {
        XCTAssertTrue(ProviderPreset.minimax.capabilities.contains(.reasoning))
    }

    func testBuiltInProviderStartsWithAnEmptyModelCatalog() {
        for preset in ProviderPreset.allCases where preset != .customOpenAI {
            let profile = preset.makeProfile()
            XCTAssertEqual(profile.availableModels, [])
            XCTAssertEqual(profile.defaultModel, "")
        }
    }

    func testReasoningEffortIsLimitedByTheSelectedModel() {
        let openAI = ProviderPreset.openai.makeProfile()
        XCTAssertEqual(openAI.supportedReasoningEfforts(for: "gpt-6.1-sol"), ReasoningEffort.allCases)
        XCTAssertEqual(openAI.supportedReasoningEfforts(for: "gpt-4o"), [])

        let deepSeek = ProviderPreset.deepseek.makeProfile()
        XCTAssertEqual(deepSeek.supportedReasoningEfforts(for: "deepseek-reasoner"), ReasoningEffort.allCases)
        XCTAssertEqual(deepSeek.supportedReasoningEfforts(for: "deepseek-chat"), [])
    }

    @MainActor
    func testSuccessfulLatestReplyDoesNotShowOlderAPIKeyError() {
        let state = ConversationState()
        let failed = Turn(sessionId: "session", role: .assistant, content: "", status: .failed)
        let succeeded = Turn(sessionId: "session", role: .assistant, content: "正常回复", status: .completed)
        state.replaceTurns([failed, succeeded], events: [])
        XCTAssertNil(state.currentErrorMessage)
    }

    func testCompatibilityUpgradeDoesNotSeedDeepSeekModelNames() {
        var legacy = ProviderPreset.deepseek.makeProfile()
        legacy.defaultModel = "deepseek-chat"
        legacy.availableModels = ["deepseek-chat", "deepseek-reasoner", "deepseek-flash"]

        let upgraded = legacy.applyingCompatibilityDefaults()
        XCTAssertEqual(upgraded.defaultModel, "deepseek-chat")
        XCTAssertEqual(upgraded.availableModels, ["deepseek-chat", "deepseek-reasoner", "deepseek-flash"])
        XCTAssertEqual(upgraded.baseURL, ProviderPreset.deepseek.defaultBaseURL)
    }

    func testLegacyMiniMaxProfileIsUpgradedWithoutChangingIdentity() {
        let legacy = ProviderProfile(
            name: "MiniMax",
            kind: .openAICompatible,
            capabilities: [.streaming],
            id: "keeps-keychain-identity",
            baseURL: "https://api.minimax.chat/v1",
            defaultModel: "MiniMax-M3",
            preset: ProviderPreset.minimax.rawValue
        )

        let upgraded = legacy.applyingCompatibilityDefaults()
        XCTAssertEqual(upgraded.id, legacy.id)
        XCTAssertEqual(upgraded.keychainCredentialRef, legacy.keychainCredentialRef)
        XCTAssertEqual(upgraded.baseURL, ProviderPreset.minimax.defaultBaseURL)
        XCTAssertEqual(upgraded.kind, .anthropic)
        XCTAssertTrue(upgraded.capabilities.contains(.reasoning))
        XCTAssertEqual(upgraded.availableModels, [])
        XCTAssertEqual(upgraded.defaultModel, "MiniMax-M3")
    }

    func testSSEParserFlushesFinalEventWithoutTrailingBlankLine() {
        var parser = SSEParser()
        let payload = #"{"choices":[{"delta":{"content":"你好"}}]}"#
        XCTAssertEqual(parser.feed("data: \(payload)"), [])
        XCTAssertEqual(parser.finish(), [payload])
        XCTAssertEqual(parser.finish(), [])
    }

    func testKimiK2UsesTheOnlyTemperatureAcceptedByChinaAndGlobalEndpoints() {
        let request = ModelRequest(safeContext: .empty(), model: "kimi-k2.6", temperature: 0.7)
        for preset in [ProviderPreset.moonshot, .kimiGlobal] {
            let body = OpenAICompatibleRequestPayload.make(
                request: request,
                messages: [["role": "user", "content": "Hello"]],
                profile: preset.makeProfile()
            )
            XCTAssertEqual(body["temperature"] as? Double, 1.0, "\(preset.displayName) must use the K2-compatible temperature")
        }
    }

    func testOtherOpenAICompatibleModelsKeepTheUserTemperature() {
        let request = ModelRequest(safeContext: .empty(), model: "deepseek-chat", temperature: 0.35)
        let body = OpenAICompatibleRequestPayload.make(
            request: request,
            messages: [["role": "user", "content": "Hello"]],
            profile: ProviderPreset.deepseek.makeProfile()
        )
        XCTAssertEqual(body["temperature"] as? Double, 0.35)
    }

    func testAnthropic46ReasoningUsesAdaptivePayload() {
        let request = ModelRequest(
            safeContext: .empty(),
            model: "claude-opus-4-6",
            reasoningEffort: .low
        )
        let body = AnthropicRequestPayload.make(
            request: request,
            messages: [ModelMessage(role: "user", content: "Hello")],
            systemPrompt: ""
        )

        XCTAssertNil(body["temperature"])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "adaptive")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertNil((body["thinking"] as? [String: Any])?["budget_tokens"])
    }

    func testLegacyAnthropicReasoningUsesBudgetWithoutUnsupportedDisplayField() {
        let request = ModelRequest(
            safeContext: .empty(),
            model: "claude-sonnet-4-5-20250929",
            reasoningEffort: .medium
        )
        let body = AnthropicRequestPayload.make(
            request: request,
            messages: [ModelMessage(role: "user", content: "Hello")],
            systemPrompt: ""
        )

        let thinking = body["thinking"] as? [String: Any]
        let thinkingType = thinking?["type"] as? String
        let thinkingBudget = thinking?["budget_tokens"] as? Int
        XCTAssertEqual(thinkingType, "enabled")
        XCTAssertEqual(thinkingBudget, 4_000)
        XCTAssertNil(thinking?["display"])
    }

    func testProviderErrorDetailKeepsOfficialMessageButRedactsCredentials() {
        let response = #"{"error":{"message":"Your credit balance is too low. Bearer sk-secret-token-123456789"}}"#
        let detail = ProviderResponseDetail.message(from: Data(response.utf8))

        XCTAssertTrue(detail.contains("Your credit balance is too low."))
        XCTAssertTrue(detail.contains("[redacted credential]"))
        XCTAssertFalse(detail.contains("sk-secret-token-123456789"))
    }

    func testProviderErrorDetailExtractsOfficialMessagesForSupportedEnvelopes() {
        let fixtures: [(provider: String, body: String, expected: String)] = [
            (
                "Anthropic",
                #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"#,
                "Your credit balance is too low"
            ),
            (
                "OpenAI-compatible / DeepSeek",
                #"{"error":{"message":"Invalid API key supplied"}}"#,
                "Invalid API key supplied"
            ),
            (
                "Ollama",
                #"{"error":"model 'gemma4:cloud' not found"}"#,
                "model 'gemma4:cloud' not found"
            ),
            (
                "MiniMax",
                #"{"base_resp":{"status_code":1004,"status_msg":"insufficient balance"}}"#,
                "insufficient balance"
            )
        ]

        for fixture in fixtures {
            let detail = ProviderResponseDetail.message(from: Data(fixture.body.utf8))
            XCTAssertEqual(detail, fixture.expected, "Expected the official \(fixture.provider) error message")
        }
    }

    func testProviderErrorDetailRecognizesErrorEnvelopesInsideSuccessfulStreams() {
        let fixtures: [(body: String, expected: String)] = [
            (#"{"error":{"message":"gateway rejected this request"}}"#, "gateway rejected this request"),
            (#"{"type":"error","error":{"message":"Anthropic stream failed"}}"#, "Anthropic stream failed"),
            (#"{"type":"response.failed","error":{"message":"Responses stream failed"}}"#, "Responses stream failed"),
            (#"{"base_resp":{"status_code":1004,"status_msg":"MiniMax balance is insufficient"}}"#, "MiniMax balance is insufficient")
        ]

        for fixture in fixtures {
            let detail = ProviderResponseDetail.errorMessageIfPresent(from: Data(fixture.body.utf8))
            XCTAssertEqual(detail, fixture.expected)
        }
        XCTAssertNil(ProviderResponseDetail.errorMessageIfPresent(from: Data(#"{"type":"message_delta","usage":{"output_tokens":8}}"#.utf8)))
    }

    func testSSEParserTreatsCRLFSeparatorAsBlankLine() {
        var parser = SSEParser()
        let payload = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}"#
        XCTAssertEqual(parser.feed("data: \(payload)\r"), [])
        XCTAssertEqual(parser.feed("\r"), [payload])
    }

    func testReasoningEffortIncludesMiniMaxThinkingDepths() {
        XCTAssertEqual(ReasoningEffort.allCases.map(\.rawValue), ["low", "medium", "high", "xhigh", "max"])
    }

    func testPromptContainsNoteTitle_andHash() {
        let locator = NoteLocator(noteId: "note-1", titleSnapshot: "重点 idea", modificationDate: Date())
        let ctx = NoteContext.fromPlaintext(locator: locator, plaintext: "给 MacBook 的备忘录做一个 AI 助手")
        let prompt = PromptBuilder.build(
            noteContext: ctx,
            history: [],
            userQuestion: "帮我整理一份可执行的产品方案",
            slashCommand: nil
        )
        let msg = prompt.messages.first?.content ?? ""
        XCTAssertTrue(msg.contains("重点 idea"))
        XCTAssertTrue(msg.contains("MacBook"))
        XCTAssertFalse(prompt.systemPrompt.isEmpty)
        XCTAssertEqual(prompt.basedOnBodyHash, ctx.bodyHash)
    }

    func testResponseLanguageFollowsQuestionRatherThanInterfaceLanguage() {
        let locator = NoteLocator(noteId: "note-english", titleSnapshot: "中文笔记", modificationDate: Date())
        let context = NoteContext.fromPlaintext(locator: locator, plaintext: "这是中文的源笔记。")

        let prompt = PromptBuilder.build(
            noteContext: context,
            history: [],
            userQuestion: "请总结"
        )

        XCTAssertTrue(prompt.systemPrompt.contains("回答使用简体中文"))
        XCTAssertFalse(prompt.systemPrompt.contains("Respond in English"))

        let englishPrompt = PromptBuilder.build(
            noteContext: context,
            history: [],
            userQuestion: "Please summarize this note."
        )
        XCTAssertTrue(englishPrompt.systemPrompt.contains("Reply in the same language"))
    }

    func testSlashCommandSummary_triggersHint() {
        let locator = NoteLocator(noteId: "note-2", titleSnapshot: "T", modificationDate: Date())
        let longBody = String(repeating: "一段文字 ", count: 200)
        let ctx = NoteContext.fromPlaintext(locator: locator, plaintext: longBody)
        let prompt = PromptBuilder.build(
            noteContext: ctx,
            history: [],
            userQuestion: "/summary",
            slashCommand: SlashCommand.match("/summary")
        )
        let msg = prompt.messages.first?.content ?? ""
        XCTAssertTrue(msg.contains("总结") || msg.contains("未决问题") || msg.contains("/summary"))
    }

    func testBuiltPromptIsSendable() {
        let locator = NoteLocator(noteId: "x", titleSnapshot: "t", modificationDate: Date())
        let ctx = NoteContext.fromPlaintext(locator: locator, plaintext: "hi")
        let p = PromptBuilder.build(noteContext: ctx, history: [], userQuestion: "hi")
        XCTAssertFalse(p.messages.isEmpty)
        XCTAssertEqual(p.messages.first?.content.isEmpty, false)
    }

    func testEgressMessageIsRebuiltOnlyFromSafeContext() {
        let safe = SafeContext(
            noteTextSnapshot: "可发送的笔记",
            userQuestion: "请解释图片",
            conversationSummary: "最近没有对话",
            imageTextSnapshot: "可发送的图片文字",
            sourceKinds: [.noteText, .userQuestion, .previousTurns, .ocrText],
            protectedReason: nil
        )

        let content = PromptBuilder.egressMessages(from: safe).first?.content ?? ""
        XCTAssertTrue(content.contains("可发送的笔记"))
        XCTAssertTrue(content.contains("可发送的图片文字"))
        XCTAssertTrue(content.contains("请解释图片"))
        XCTAssertFalse(content.contains("本机图片识别："))
    }
}

private final class CountingKeychainBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let value: Data?
    private var reads = 0

    init(value: Data?) { self.value = value }

    var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func save(_ data: Data, ref: String) throws {}

    func read(ref: String) throws -> Data? {
        lock.lock(); reads += 1; lock.unlock()
        return value
    }

    func delete(ref: String) throws {}
}
