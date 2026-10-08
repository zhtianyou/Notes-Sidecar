import XCTest
@testable import NotesSidecar

final class FirewallTests: XCTestCase {
    func testCanaryCredentials_areAllCaught() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let canaries: [(String, String)] = [
            ("sk-abcdef0123456789abcdef0123456789", "openAIStyleKey"),
            ("sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789", "anthropicStyleKey"),
            ("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABC", "githubToken"),
            ("AKIAIOSFODNN7EXAMPLE", "awsAccessKey"),
            ("Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature", "jwtToken"),
            ("-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAK...", "privateKeyBlock"),
            ("email me@example.com 密码 hunter2hunter_more_text", "passwordProximity"),
            ("api_key = \"abc123xyz_extra_padding_1234\"", "apiKeyAssignment"),
        ]
        for (canary, _) in canaries {
            let eval = await firewall.evaluate(
                noteText: canary,
                userQuestion: "请问这里有什么风险？",
                conversationSummary: "测试",
                requestId: UUID().uuidString
            )
            XCTAssertFalse(eval.findings.isEmpty,
                "预期从「\(canary.prefix(40))」中命中凭据，实际无命中")
        }
    }

    func testPlainTokenAndAppCredentials_areCaughtWithoutQuotes() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let canaries = [
            "App Secret: exampleSecretValue1234567890",
            "App ID: cli_exampleIdentifier123456",
            "access_token = exampleAccessToken1234567890",
            "refresh-token：exampleRefreshToken1234567890",
            "token: exampleGenericToken1234567890",
        ]

        for canary in canaries {
            let result = await firewall.evaluate(
                noteText: canary,
                userQuestion: "检查凭据",
                conversationSummary: "",
                requestId: UUID().uuidString
            )
            XCTAssertFalse(result.findings.isEmpty, "未识别明文凭据字段：\(canary)")
            XCTAssertFalse(result.status.sourceKinds.contains(.noteText))
        }
    }

    func testWordTokenWithoutAssignedValue_isNotAFalsePositive() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluate(
            noteText: "飞书机器人 token 的权限设计说明",
            userQuestion: "总结这篇笔记",
            conversationSummary: "",
            requestId: "plain-token-word"
        )

        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertTrue(result.status.sourceKinds.contains(.noteText))
    }

    func testSensitiveNoteLinesAreRemovedWhileSafeLinesRemain() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluate(
            noteText: """
            项目：机器人权限梳理
            App Secret: exampleSecretValue1234567890
            下一步：本周完成回归测试
            """,
            userQuestion: "总结下一步",
            conversationSummary: "",
            requestId: "partial-note-redaction"
        )

        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertTrue(result.status.noteTextSnapshot.contains("机器人权限梳理"))
        XCTAssertTrue(result.status.noteTextSnapshot.contains("本周完成回归测试"))
        XCTAssertFalse(result.status.noteTextSnapshot.contains("exampleSecretValue"))
        XCTAssertTrue(result.status.sourceKinds.contains(.noteText))
    }

    func testSensitiveQuestionLineIsRemovedWhileSafeQuestionRemains() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluate(
            noteText: "公开项目说明",
            userQuestion: "请总结下一步\nApp Secret: exampleSecretValue1234567890\n并列出风险",
            conversationSummary: "",
            requestId: "partial-question-redaction"
        )
        XCTAssertTrue(result.status.userQuestion.contains("总结下一步"))
        XCTAssertTrue(result.status.userQuestion.contains("列出风险"))
        XCTAssertFalse(result.status.userQuestion.contains("exampleSecretValue"))
        XCTAssertTrue(result.status.sourceKinds.contains(.userQuestion))
    }

    func testScanFailedClosed_returnsProtectedContext() async {
        let firewall = SensitiveContentFirewall.shared
        let eval = await firewall.evaluate(
            noteText: "无凭据的普通文本",
            userQuestion: "测试",
            conversationSummary: "",
            requestId: "test"
        )
        if !eval.failedClosed {
            XCTAssertNil(eval.status.protectedReason)
        }
    }

    func testCleanText_passesThrough() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let eval = await firewall.evaluate(
            noteText: "这是一篇关于产品方案的笔记，今天我们讨论了三层架构。",
            userQuestion: "帮我提炼三条行动项",
            conversationSummary: "",
            requestId: "test"
        )
        XCTAssertFalse(eval.failedClosed)
        XCTAssertNil(eval.status.protectedReason)
        XCTAssertTrue(eval.findings.isEmpty)
        XCTAssertEqual(eval.status.manifestHash.count, 32)
        XCTAssertNotEqual(eval.status.manifestHash, String(repeating: "0", count: 32))
    }

    func testTableauFieldNamedPhoneNumberIsNotTreatedAsStreetAddress() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let tableauFormula = "{ FIXED [手机号] : SUM(IF [订单状态] = \"已完成\" THEN 1 ELSE 0 END) }"

        let result = await firewall.evaluate(
            noteText: tableauFormula,
            userQuestion: "解释这个计算公式",
            conversationSummary: "",
            requestId: "tableau-field-name-false-positive"
        )

        XCTAssertTrue(result.findings.isEmpty, "Field labels and formula literals must not be treated as personal data")
        XCTAssertEqual(result.status.noteTextSnapshot, tableauFormula)
        XCTAssertNil(result.status.protectedReason)
    }

    func testStructuredStreetAddressRemainsProtected() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluate(
            noteText: "请寄到北京市海淀区知春路76号。",
            userQuestion: "整理信息",
            conversationSummary: "",
            requestId: "structured-address-still-protected"
        )

        XCTAssertTrue(result.findings.contains(where: { $0.kind == .preciseAddress }))
        XCTAssertFalse(result.status.sourceKinds.contains(.noteText))
    }

    func testSafeContextManifestHash_isStableAndContentSensitive() {
        let first = SafeContext(
            noteTextSnapshot: "笔记 A",
            userQuestion: "总结",
            conversationSummary: "",
            sourceKinds: [.noteText, .userQuestion],
            protectedReason: nil
        )
        let same = SafeContext(
            noteTextSnapshot: "笔记 A",
            userQuestion: "总结",
            conversationSummary: "",
            sourceKinds: [.noteText, .userQuestion],
            protectedReason: nil
        )
        let changed = SafeContext(
            noteTextSnapshot: "笔记 B",
            userQuestion: "总结",
            conversationSummary: "",
            sourceKinds: [.noteText, .userQuestion],
            protectedReason: nil
        )

        XCTAssertEqual(first.manifestHash, same.manifestHash)
        XCTAssertNotEqual(first.manifestHash, changed.manifestHash)
        XCTAssertEqual(first.manifestHash.count, 32)
    }

    func testUrlQueryExclusion_removesSuspectKeys() async {
        let firewall = SensitiveContentFirewall.shared
        let url = URL(string: "https://example.com/cb?token=abc123&safe=ok")!
        let cleaned = await firewall.isExcluded(url)
        let s = cleaned?.absoluteString ?? ""
        XCTAssertFalse(s.contains("token="))
        XCTAssertTrue(s.contains("safe=ok"))
    }

    func testImageOCRPrivacy_removesPrivateLinesAndKeepsSafeLines() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluateImageOCR("""
        会议主题：产品发布计划
        姓名：张三
        联系电话：13800138000
        下一步：周五完成测试
        """)

        XCTAssertFalse(result.failedClosed)
        XCTAssertEqual(result.excludedLineCount, 2)
        XCTAssertTrue(result.safeText.contains("产品发布计划"))
        XCTAssertTrue(result.safeText.contains("周五完成测试"))
        XCTAssertFalse(result.safeText.contains("张三"))
        XCTAssertFalse(result.safeText.contains("13800138000"))
        XCTAssertTrue(result.findings.contains(where: { $0.kind == .personName }))
        XCTAssertTrue(result.findings.contains(where: { $0.kind == .phoneNumber }))
    }

    func testImageOCRPrivacy_excludesCredentialCanary() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let result = await firewall.evaluateImageOCR("""
        可公开的产品说明
        API Key: sk-abcdef0123456789abcdef0123456789
        """)

        XCTAssertEqual(result.safeText, "可公开的产品说明")
        XCTAssertEqual(result.excludedLineCount, 1)
        XCTAssertTrue(result.findings.contains(where: { $0.kind == .openAIStyleKey }))
    }

    func testFinalEgressFirewallCannotReintroduceRejectedImageText() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let canary = "sk-abcdef0123456789abcdef0123456789"
        let result = await firewall.evaluate(
            noteText: "普通笔记正文",
            userQuestion: "请总结",
            conversationSummary: "",
            imageText: "图片里的密钥 \(canary)",
            requestId: "image-egress-canary"
        )

        XCTAssertEqual(result.status.imageTextSnapshot, "")
        XCTAssertFalse(result.status.sourceKinds.contains(.ocrText))
        XCTAssertTrue(result.findings.contains(where: { $0.source == .ocrText }))
        let outbound = PromptBuilder.egressMessages(from: result.status).first?.content ?? ""
        XCTAssertFalse(outbound.contains(canary))
        XCTAssertTrue(outbound.contains("普通笔记正文"))
    }

    func testCredentialCanaryBlocksProviderInvocationAndNetworkEgress() async {
        let firewall = SensitiveContentFirewall.shared
        await firewall.load()
        let spy = NetworkSpyProvider()
        let router = ModelRouter(providerFactory: { _ in spy })
        let canary = "sk-abcdef0123456789abcdef0123456789"
        let profile = ProviderProfile(
            name: "Network spy",
            kind: .openAICompatible,
            capabilities: [.streaming],
            baseURL: "https://should-never-be-contacted.invalid/v1",
            defaultModel: "should-never-run"
        )
        let context = SafeContext(
            noteTextSnapshot: "API Key: \(canary)",
            userQuestion: "Please review this secret: \(canary)",
            conversationSummary: "",
            sourceKinds: [.noteText, .userQuestion],
            protectedReason: nil
        )
        let manifestCount = LockedCounter()

        do {
            _ = try await router.egress(
                requestId: "credential-canary-no-network",
                safeContext: context,
                profile: profile,
                systemPrompt: "",
                onEvent: { _ in },
                manifestSink: { _ in manifestCount.increment() }
            )
            XCTFail("A fully protected context must never reach a provider")
        } catch {
            // The firewall refusal is the expected result.
        }

        XCTAssertEqual(spy.streamInvocationCount, 0, "Privacy rejection must produce zero provider/network calls")
        XCTAssertEqual(manifestCount.value, 0, "No egress manifest may be emitted for a rejected request")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.lock(); storage += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
}

private final class NetworkSpyProvider: ModelProvider, @unchecked Sendable {
    nonisolated let capabilities: ProviderCapabilities = [.streaming]
    private let invocationCounter = LockedCounter()

    var streamInvocationCount: Int { invocationCounter.value }

    func testConnection() async throws {}

    func stream(_ request: ModelRequest,
                messages: [ModelMessage],
                systemPrompt: String) -> AsyncThrowingStream<ModelEvent, Error> {
        invocationCounter.increment()
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
