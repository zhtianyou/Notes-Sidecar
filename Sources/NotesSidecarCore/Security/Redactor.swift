import Foundation

public struct Redactor: Sendable {
    public static let shared = Redactor()

    private let sensitiveHeaderNames: Set<String> = [
        "authorization", "x-api-key", "api-key", "x-auth-token", "cookie", "set-cookie", "openai-organization"
    ]

    public init() {}

    /// 通用脱敏：用于日志与崩溃报告。返回红星+末四位（与 Keychain 风格对齐）。
    public func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 4 { return String(repeating: "•", count: max(4, trimmed.count)) }
        let tail = trimmed.suffix(4)
        return "•••" + tail
    }

    public func redact(_ headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            if sensitiveHeaderNames.contains(k.lowercased()) {
                out[k] = redact(v)
            } else {
                out[k] = v
            }
        }
        return out
    }

    /// 截断正文，避免把整篇笔记写进日志
    public func truncateBody(_ text: String, max: Int = 80) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= max { return oneLine }
        return String(oneLine.prefix(max)) + "…"
    }
}