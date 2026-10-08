import Foundation
import CryptoKit

/// P0 隐私不变量：远程模型请求只接收 `SafeContext` 文字。
/// `SafeContext` 是 `RawContextBundle` 经 `SensitiveContentFirewall` 评估后保留下来的纯文本。
/// 类型层面阻止 Provider 模块接收任何原始附件、URL、本地文件引用或凭据命中片段。
public struct SafeContext: Sendable, Hashable, Codable {
    public let noteTextSnapshot: String
    public let userQuestion: String
    public let conversationSummary: String
    public let imageTextSnapshot: String
    public let audioTranscriptSnapshot: String
    public let sourceKinds: Set<SafeSourceKind>
    public let protectedReason: ProtectedReason?
    public let manifestHash: String

    /// 真正基于内容算 hash 的初始化 —— 不允许传 "0" / "00000000" 这种占位符。
    public init(noteTextSnapshot: String, userQuestion: String, conversationSummary: String,
                imageTextSnapshot: String = "", audioTranscriptSnapshot: String = "",
                sourceKinds: Set<SafeSourceKind>, protectedReason: ProtectedReason?) {
        self.noteTextSnapshot = noteTextSnapshot
        self.userQuestion = userQuestion
        self.conversationSummary = conversationSummary
        self.imageTextSnapshot = imageTextSnapshot
        self.audioTranscriptSnapshot = audioTranscriptSnapshot
        self.sourceKinds = sourceKinds
        self.protectedReason = protectedReason
        self.manifestHash = Self.computeHash(
            note: noteTextSnapshot,
            question: userQuestion,
            summary: conversationSummary,
            imageText: imageTextSnapshot,
            audioTranscript: audioTranscriptSnapshot,
            protectedReason: protectedReason
        )
    }

    private static func computeHash(note: String, question: String, summary: String,
                                    imageText: String, audioTranscript: String,
                                    protectedReason: ProtectedReason?) -> String {
        let payload = [note, question, summary, imageText, audioTranscript, protectedReason?.rawValue ?? ""].joined(separator: "\u{001F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public enum SafeSourceKind: String, Codable, Hashable, Sendable, CaseIterable {
        case noteText
        case userQuestion
        case previousTurns
        case slashCommandHint
        case ocrText              // P1：图片本地 OCR 后进入
        case audioTranscript      // P1：录音本机转写后进入
        case webPageText          // P1：链接本机抓取正文后进入

        public var displayName: String {
            switch self {
            case .noteText: return "笔记正文"
            case .userQuestion: return "用户问题"
            case .previousTurns: return "历史对话"
            case .slashCommandHint: return "快捷动作"
            case .ocrText: return "OCR 文本"
            case .audioTranscript: return "音频转写"
            case .webPageText: return "网页正文"
            }
        }
    }

    public enum ProtectedReason: String, Codable, Hashable, Sendable {
        case credentialDetected
        case scanFailedClosed
        case exifGpsPresent
        case protectedByUser
    }

    public var isProtected: Bool { protectedReason != nil }
    public var isEmpty: Bool {
        noteTextSnapshot.isEmpty && userQuestion.isEmpty && conversationSummary.isEmpty && imageTextSnapshot.isEmpty && audioTranscriptSnapshot.isEmpty
    }

    public static func empty() -> SafeContext {
        SafeContext(noteTextSnapshot: "", userQuestion: "", conversationSummary: "",
                    sourceKinds: [], protectedReason: nil)
    }
}

/// 出站清单：记录「这条请求要发什么/不发什么」，是隐私门之后的审计产物。
/// 不记录原文，只记 hash + 来源类型 + 策略版本 + 目标域名。
public struct EgressManifest: Sendable, Hashable, Codable {
    public let requestId: String
    public let providerId: String
    public let targetHost: String
    public let model: String
    public let includedSources: Set<SafeContext.SafeSourceKind>
    public let excludedSourceKinds: Set<SafeContext.SafeSourceKind>
    public let policyVersion: String
    public let safeContextHash: String
    public let createdAt: Date

    public init(requestId: String, providerId: String, targetHost: String, model: String,
                includedSources: Set<SafeContext.SafeSourceKind>,
                excludedSourceKinds: Set<SafeContext.SafeSourceKind>,
                safeContextHash: String,
                policyVersion: String = SensitiveContentFirewall.policyVersion,
                createdAt: Date = .init()) {
        self.requestId = requestId
        self.providerId = providerId
        self.targetHost = targetHost
        self.model = model
        self.includedSources = includedSources
        self.excludedSourceKinds = excludedSourceKinds
        self.safeContextHash = safeContextHash
        self.policyVersion = policyVersion
        self.createdAt = createdAt
    }
}
