import Foundation

public struct SlashCommand: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let trigger: String
    public let displayName: String
    public let promptHint: String
    public let iconName: String

    public init(id: String, trigger: String, displayName: String, promptHint: String, iconName: String = "scope") {
        self.id = id; self.trigger = trigger; self.displayName = displayName; self.promptHint = promptHint; self.iconName = iconName
    }

    public var description: String { "\(displayName) · \(trigger)" }
}

public extension SlashCommand {
    static let all: [SlashCommand] = [
        .init(id: "summary",   trigger: "/summary",   displayName: "总结",     promptHint: "请总结这篇笔记，保留事实层级和未决问题。"),
        .init(id: "tasks",     trigger: "/tasks",     displayName: "提炼任务", promptHint: "请提炼任务，输出任务、负责人、截止时间、依赖。"),
        .init(id: "structure", trigger: "/structure", displayName: "整理结构", promptHint: "请重组标题、层级和段落，不要虚构事实。"),
        .init(id: "rewrite",   trigger: "/rewrite",   displayName: "改写",     promptHint: "请改写，保留原意，可指定语气。"),
        .init(id: "brainstorm",trigger: "/brainstorm",displayName: "继续发散", promptHint: "请给出不同方向及取舍。"),
        .init(id: "question",  trigger: "/question",  displayName: "反向提问", promptHint: "请找出信息缺口并提出澄清问题。"),
        .init(id: "translate", trigger: "/translate", displayName: "翻译",     promptHint: "请翻译并保持格式。")
    ]

    static func match(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return all.first { $0.trigger == firstToken }
    }
}