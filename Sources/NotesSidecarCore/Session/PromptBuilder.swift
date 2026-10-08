import Foundation

public struct BuiltPrompt: Sendable {
    public let systemPrompt: String
    public let messages: [ModelMessage]
    public let summary: String
    public let outboundQuestion: String
    public let basedOnBodyHash: String
}

public enum PromptBuilder {
    private static let systemHead = """
    你是 Notes Sidecar —— 一位 Apple Notes 的本地优先 AI 边栏。下面给的「笔记正文」是用户当前在 Notes 选中笔记的纯文本副本，hash 字段是 16 位摘要（用于漂移检测）。请按下列规则回答：

    1. 只基于「笔记正文」与可选的「本机图片上下文」中可读到的内容作答，不要虚构事实。
    2. 不要复述或外泄任何 API Key、Token、私钥、Cookie、用户名+密码组合、邮箱地址。如果正文里同时出现了用户名/账号和密码，规则上一律不外发；本规则没有关闭开关。
    3. {{RESPONSE_LANGUAGE}}
    4. 当用户问题涉及"写回"，先给出「将写回的内容预览」，等用户明确确认后再写动作。
    5. 不要展示模型内部思维链；只能输出可直接阅读的回答与必要的可验证事实。
    """

    public static func build(noteContext: NoteContext,
                             history: [Turn],
                             userQuestion: String,
                             imageContext: String = "",
                             slashCommand: SlashCommand? = nil) -> BuiltPrompt {
        let summary = makeSummary(turns: history, selection: noteContext.selection, bodyText: noteContext.plaintext)

        var instruction = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = slashCommand {
            instruction = "\(slash.promptHint)\n\n用户原话：\(instruction)"
        }

        let body = noteContext.plaintext
        let imageSection = imageContext.isEmpty ? "" : """

        === 本机图片上下文开始 ===
        \(imageContext)
        === 本机图片上下文结束 ===
        """
        let header = """
        === 当前笔记 ===
        标题：\(noteContext.locator.titleSnapshot)
        字数：\(body.count)
        修改时间：\(Self.dateFmt.string(from: noteContext.locator.modificationDate))
        Hash：\(noteContext.bodyHash)
        === 正文开始 ===
        \(body)
        === 正文结束 ===
        \(imageSection)

        \(summary)

        === 用户问题 ===
        \(instruction)
        """

        // The interface language controls the UI only. A reply should follow
        // the language in the user's actual message, not the language chosen
        // for menus or the language of the source note.
        let responseLanguage = responseLanguageInstruction(for: instruction)
        let sys = systemHead
            .replacingOccurrences(of: "{{RESPONSE_LANGUAGE}}", with: responseLanguage)
            .replacingOccurrences(of: "(#)占位#(\\(基于\\))", with: "\(noteContext.bodyHash.prefix(8))", options: .regularExpression)

        let msgs: [ModelMessage] = [
            ModelMessage(role: "user", content: header)
        ]
        return BuiltPrompt(
            systemPrompt: sys,
            messages: msgs,
            summary: summary,
            outboundQuestion: instruction,
            basedOnBodyHash: noteContext.bodyHash
        )
    }

    private static func responseLanguageInstruction(for question: String) -> String {
        let scalars = question.unicodeScalars
        let hanCount = scalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let latinCount = scalars.filter {
            (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
        }.count

        if hanCount > 0, hanCount >= latinCount / 2 {
            return "回答使用简体中文，简洁、清晰；可用 Markdown（标题/列表/引用/代码/表格）。"
        }
        return "Reply in the same language as the user's question. Keep the response concise and clear; Markdown is allowed."
    }

    /// 最终出站消息只能从防火墙裁决后的 SafeContext 重建，不能复用原始 Prompt。
    public static func egressMessages(from safe: SafeContext) -> [ModelMessage] {
        var sections: [String] = []
        if !safe.noteTextSnapshot.isEmpty {
            sections.append("""
            === 笔记正文开始 ===
            \(safe.noteTextSnapshot)
            === 笔记正文结束 ===
            """)
        }
        if !safe.imageTextSnapshot.isEmpty {
            sections.append("""
            === 本机图片上下文开始 ===
            \(safe.imageTextSnapshot)
            === 本机图片上下文结束 ===
            """)
        }
        if !safe.audioTranscriptSnapshot.isEmpty {
            sections.append("""
            === 本机音频转写开始 ===
            \(safe.audioTranscriptSnapshot)
            === 本机音频转写结束 ===
            """)
        }
        if !safe.conversationSummary.isEmpty {
            sections.append(safe.conversationSummary)
        }
        if !safe.userQuestion.isEmpty {
            sections.append("=== 用户问题 ===\n\(safe.userQuestion)")
        }
        return [ModelMessage(role: "user", content: sections.joined(separator: "\n\n"))]
    }

    private static func makeSummary(turns: [Turn], selection: NoteContext.SelectionRange?, bodyText: String) -> String {
        var lines: [String] = ["=== 会话摘要（最近 \(min(turns.count, 6)) 轮） ==="]
        for t in turns.suffix(6) {
            let prefix = t.role == .user ? "U" : "A"
            let one = t.content.replacingOccurrences(of: "\n", with: " ")
            lines.append("[\(prefix)] " + String(one.prefix(160)))
        }
        if let sel = selection, sel.length > 0, sel.start < bodyText.count {
            let end = min(sel.start + sel.length, bodyText.count)
            let startIdx = bodyText.index(bodyText.startIndex, offsetBy: sel.start)
            let endIdx = bodyText.index(bodyText.startIndex, offsetBy: end)
            let snippet = String(bodyText[startIdx..<endIdx])
            lines.append("=== 当前选区 ===")
            lines.append(String(snippet.prefix(400)))
        }
        return lines.joined(separator: "\n")
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
