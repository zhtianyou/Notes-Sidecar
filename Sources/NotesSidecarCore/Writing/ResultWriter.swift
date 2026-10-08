import Foundation
import AppKit

/// 把模型常见的 Markdown 子集转换成 Notes 可接受的安全 HTML。
/// 未识别语法按纯文本处理，所有原始 HTML 都会被转义，避免破坏现有笔记结构。
public enum NotesHTMLRenderer {
    public static func render(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var html: [String] = []
        var index = 0
        var inCodeBlock = false
        var codeLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll(keepingCapacity: true)
                }
                inCodeBlock.toggle()
                index += 1
                continue
            }
            if inCodeBlock {
                codeLines.append(line)
                index += 1
                continue
            }
            if isTableHeader(lines: lines, index: index) {
                let headers = tableCells(line)
                html.append("<table><thead><tr>\(headers.map { "<th>\(inline($0))</th>" }.joined())</tr></thead><tbody>")
                index += 2
                while index < lines.count, looksLikeTableRow(lines[index]) {
                    let cells = tableCells(lines[index])
                    html.append("<tr>\(cells.map { "<td>\(inline($0))</td>" }.joined())</tr>")
                    index += 1
                }
                html.append("</tbody></table>")
                continue
            }
            if let item = unorderedItem(trimmed) {
                var items = [item]
                index += 1
                while index < lines.count, let next = unorderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                html.append("<ul>\(items.map { "<li>\(inline($0))</li>" }.joined())</ul>")
                continue
            }
            if let item = orderedItem(trimmed) {
                var items = [item]
                index += 1
                while index < lines.count, let next = orderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                html.append("<ol>\(items.map { "<li>\(inline($0))</li>" }.joined())</ol>")
                continue
            }

            if trimmed.isEmpty {
                html.append("<br>")
            } else if trimmed == "---" || trimmed == "***" {
                html.append("<hr>")
            } else if let heading = heading(trimmed) {
                html.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
            } else if trimmed.hasPrefix("> ") {
                html.append("<blockquote>\(inline(String(trimmed.dropFirst(2))))</blockquote>")
            } else {
                html.append("<p>\(inline(line))</p>")
            }
            index += 1
        }
        if inCodeBlock {
            html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        return html.joined(separator: "\n")
    }

    private static func inline(_ value: String) -> String {
        var output = escape(value.trimmingCharacters(in: .whitespaces))
        output = replacing(output, pattern: #"`([^`]+)`"#, template: "<code>$1</code>")
        output = replacing(output, pattern: #"\*\*([^*]+)\*\*"#, template: "<strong>$1</strong>")
        output = replacing(output, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, template: "<em>$1</em>")
        return output
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func replacing(_ value: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func unorderedItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let number = line[..<dot]
        let afterDot = line.index(after: dot)
        guard number.allSatisfy(\.isNumber), afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|") && tableCells(line).count >= 2
    }

    private static func isTableHeader(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count, looksLikeTableRow(lines[index]) else { return false }
        let separators = tableCells(lines[index + 1])
        return separators.count >= 2 && separators.allSatisfy {
            let cell = $0.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return cell.count >= 3 && cell.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

public actor ResultWriter {
    public static let shared = ResultWriter()
    private init() {}

    public struct PreviewBlock: Sendable {
        public let title: String
        public let body: String
        public let expectedAppendChars: Int
    }

    public struct AppendPlan: Identifiable, Sendable {
        public let id: UUID
        public let answer: String
        public let preview: PreviewBlock
        public let source: NoteContext

        public init(id: UUID = UUID(), answer: String, preview: PreviewBlock, source: NoteContext) {
            self.id = id
            self.answer = answer
            self.preview = preview
            self.source = source
        }
    }

    public enum SafeAppendError: Error, LocalizedError, Equatable, Sendable {
        case selectionChanged(expectedTitle: String, actualTitle: String)
        case noteChanged(title: String)

        public var errorDescription: String? {
            switch self {
            case let .selectionChanged(expected, actual):
                return SidecarLocalizer.text("当前选中的是「\(actual)」，目标笔记「\(expected)」未写入。", "“\(actual)” is selected, so “\(expected)” was not updated.")
            case let .noteChanged(title):
                return SidecarLocalizer.text("「\(title)」在生成后发生了变化，尚未写入。", "“\(title)” changed after generation and was not updated.")
            }
        }
    }

    public enum Mode: Sendable { case copy, append, newNote }

    public func makeAppendPlan(answer: String, source: NoteContext, now: Date = .init()) -> AppendPlan {
        AppendPlan(
            answer: answer,
            preview: buildPreview(answer: answer, mode: .append, noteTitle: source.locator.titleSnapshot, now: now),
            source: source
        )
    }

    /// 写入前重新读取当前 Notes 快照。目标或正文版本变化时停止，不静默覆盖用户修改。
    public func appendSafely(
        plan: AppendPlan,
        contextProvider: NotesContextProviding,
        writer: NotesWriting
    ) async throws {
        let current = try await contextProvider.currentContext()
        guard current.locator.noteId == plan.source.locator.noteId else {
            throw SafeAppendError.selectionChanged(
                expectedTitle: plan.source.locator.titleSnapshot,
                actualTitle: current.locator.titleSnapshot
            )
        }
        guard current.bodyHash == plan.source.bodyHash else {
            throw SafeAppendError.noteChanged(title: current.locator.titleSnapshot)
        }
        do {
            try await writer.appendToNote(
                noteId: plan.source.locator.noteId,
                body: plan.preview.body,
                expectedPlaintext: plan.source.plaintext
            )
        } catch let error as BridgeError {
            switch error {
            case .selectionChanged(let actualTitle):
                throw SafeAppendError.selectionChanged(
                    expectedTitle: plan.source.locator.titleSnapshot,
                    actualTitle: actualTitle
                )
            case .noteChanged:
                throw SafeAppendError.noteChanged(title: plan.source.locator.titleSnapshot)
            default:
                throw error
            }
        }
    }

    public func rebaseAppendPlan(
        _ plan: AppendPlan,
        contextProvider: NotesContextProviding,
        now: Date = .init()
    ) async throws -> AppendPlan {
        let current = try await contextProvider.currentContext()
        guard current.locator.noteId == plan.source.locator.noteId else {
            throw SafeAppendError.selectionChanged(
                expectedTitle: plan.source.locator.titleSnapshot,
                actualTitle: current.locator.titleSnapshot
            )
        }
        return AppendPlan(
            id: plan.id,
            answer: plan.answer,
            preview: buildPreview(answer: plan.answer, mode: .append, noteTitle: current.locator.titleSnapshot, now: now),
            source: current
        )
    }

    public func buildPreview(answer: String, mode: Mode, noteTitle: String?, now: Date = .init()) -> PreviewBlock {
        let formatter = DateFormatter()
        formatter.locale = SidecarLocalizer.usesSimplifiedChinese
            ? Locale(identifier: "zh_Hans_CN")
            : Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = SidecarLocalizer.text("yyyy 年 M 月 d 日 HH:mm", "yyyy-MM-dd HH:mm")
        let stamp = formatter.string(from: now)
        let title = SidecarLocalizer.text("AI 回答 · \(stamp)", "AI Response · \(stamp)")
        let body: String
        switch mode {
        case .copy:
            body = answer
        case .append:
            body = "\n\n---\n**\(title)**\n\n\(answer)\n"
        case .newNote:
            body = "**\(title)**\n\n\(answer)"
        }
        return PreviewBlock(title: title, body: body, expectedAppendChars: body.count)
    }

    public func write(answer: String, mode: Mode, note: NoteLocator?, writer: NotesWriting) async throws -> String {
        let preview = buildPreview(answer: answer, mode: mode, noteTitle: note?.titleSnapshot)
        switch mode {
        case .copy:
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(preview.body, forType: .string)
            }
            return SidecarLocalizer.text("已复制", "Copied")
        case .append:
            guard let n = note else { throw BridgeError.noSelection }
            try await writer.appendToNote(noteId: n.noteId, body: preview.body)
            return SidecarLocalizer.text("已追加", "Appended")
        case .newNote:
            return try await writer.createNote(title: preview.title, body: preview.body)
        }
    }
}
