import Foundation

public enum AppleScriptError: Error, LocalizedError, Sendable {
    case notesNotRunning
    case noSelection
    case automationDenied
    case timeout
    case selectionChanged(String)
    case noteChanged
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notesNotRunning:   return "Notes 未运行"
        case .noSelection:       return "未选笔记"
        case .automationDenied:  return "AppleEvents 权限被拒绝（-1743）"
        case .timeout:           return "AppleScript 超时"
        case .selectionChanged(let title): return "当前选中的笔记已变为「\(title)」"
        case .noteChanged:       return "笔记正文已发生变化"
        case .scriptFailed(let s): return "脚本失败：\(s)"
        }
    }
}

/// AppleScript 桥接（actor 隔离）。MVP 只覆盖「读当前选中笔记 / 追加正文 / 新建笔记」。
///
/// 脚本必须由 App 进程自身执行。若在 App Sandbox 中启动 `/usr/bin/osascript`，
/// Apple Event 的发送者会变成子进程，主 App 的 Notes 自动化 entitlement 无法正确生效。
public actor AppleScriptBridge {
    public struct ReadPayload: Decodable, Sendable {
        public let id: String?
        public let title: String?
        public let modDate: String?
        public let body: String?
        public let html: String?
    }

    public init() {}

    /// 读当前选中笔记（id / title / modDate / body / html）。
    public func readCurrent(timeout: TimeInterval) async throws -> ReadPayload {
        let timeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let script = Self.readCurrentScript(timeoutSeconds: timeoutSeconds)
        let raw = try await run(script: script)
        try Self.assertOk(raw)
        guard let data = raw.data(using: .utf8) else { throw AppleScriptError.scriptFailed("non-utf8") }
        do {
            return try JSONDecoder().decode(ReadPayload.self, from: data)
        } catch {
            throw AppleScriptError.scriptFailed("decode: \(error.localizedDescription)")
        }
    }

    /// Keep this script inspectable by tests: Notes returns a list of object
    /// specifiers whose indirect `item 1 of variable` form can fail with -1700,
    /// especially in search results and notes containing attachments.
    static func readCurrentScript(timeoutSeconds: Int) -> String {
        """
        on jsonEscape(s)
            set t to s
            set t to my replaceText(t, "\\\\", "\\\\\\\\")
            set t to my replaceText(t, "\\"", "\\\\\\"")
            set t to my replaceText(t, (ASCII character 10), "\\\\n")
            set t to my replaceText(t, (ASCII character 13), "\\\\r")
            set t to my replaceText(t, (ASCII character 9), "\\\\t")
            return t
        end jsonEscape

        on replaceText(src, find, repl)
            set tid to AppleScript's text item delimiters
            set AppleScript's text item delimiters to find
            set parts to text items of src
            set AppleScript's text item delimiters to repl
            set joined to parts as text
            set AppleScript's text item delimiters to tid
            return joined
        end replaceText

        on run
            try
                with timeout of \(timeoutSeconds) seconds
                    tell application "Notes"
                        if not running then return "ERR:NOTES_NOT_RUNNING"
                        if (count of selection) is 0 then return "ERR:NO_SELECTION"
                        set sel to first item of (get selection)
                        set nId to id of sel
                        set nTitle to name of sel
                        set nBody to plaintext of sel
                        set nMod to (modification date of sel) as string
                        try
                            set nHTML to body of sel
                        on error
                            set nHTML to ""
                        end try
                    end tell
                end timeout
                set out to "{"
                set out to out & "\\"id\\":\\"" & my jsonEscape(nId) & "\\","
                set out to out & "\\"title\\":\\"" & my jsonEscape(nTitle) & "\\","
                set out to out & "\\"modDate\\":\\"" & my jsonEscape(nMod) & "\\","
                set out to out & "\\"body\\":\\"" & my jsonEscape(nBody) & "\\","
                set out to out & "\\"html\\":\\"" & my jsonEscape(nHTML) & "\\""
                set out to out & "}"
                return out
            on error errMsg number errNum
                if errNum is -1743 then return "ERR:AUTOMATION_DENIED"
                if errNum is -1700 then return "ERR:SELECTION_INVALID"
                return "ERR:SCRIPT:" & errNum & ":" & errMsg
            end try
        end run
        """
    }

    public func appendToNote(noteId: String, body: String, timeout: TimeInterval) async throws {
        let safeId = escapeForAS(noteId)
        let safeBody = escapeForAS(NotesHTMLRenderer.render(body))
        let timeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let script = """
        on run
            try
                with timeout of \(timeoutSeconds) seconds
                    tell application "Notes"
                        if not running then return "ERR:NOTES_NOT_RUNNING"
                        set theNote to first note whose id is "\(safeId)"
                        set newHTML to (body of theNote) & (ASCII character 10) & (ASCII character 10) & "\(safeBody)"
                        set body of theNote to newHTML
                    end tell
                end timeout
                return "OK"
            on error errMsg number errNum
                if errNum is -1743 then return "ERR:AUTOMATION_DENIED"
                return "ERR:SCRIPT:" & errNum & ":" & errMsg
            end try
        end run
        """
        let raw = try await run(script: script)
        try Self.assertOk(raw)
    }

    /// 在同一 Apple Event 中校验选中目标和原文，再执行追加，避免“先检查、后写入”的竞态。
    public func appendToNote(
        noteId: String,
        body: String,
        expectedPlaintext: String,
        timeout: TimeInterval
    ) async throws {
        let safeId = escapeForAS(noteId)
        let safeBody = escapeForAS(NotesHTMLRenderer.render(body))
        let safeExpected = escapeForAS(expectedPlaintext)
        let timeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let script = """
        on run
            try
                with timeout of \(timeoutSeconds) seconds
                    tell application "Notes"
                        if not running then return "ERR:NOTES_NOT_RUNNING"
                        set selectedNotes to selection
                        if (count of selectedNotes) is 0 then return "ERR:NO_SELECTION"
                        set selectedNote to item 1 of selectedNotes
                        if (id of selectedNote) is not "\(safeId)" then
                            return "ERR:SELECTION_CHANGED:" & (name of selectedNote)
                        end if

                        set theNote to first note whose id is "\(safeId)"
                        if (plaintext of theNote) is not "\(safeExpected)" then
                            return "ERR:NOTE_CHANGED"
                        end if

                        set newHTML to (body of theNote) & (ASCII character 10) & (ASCII character 10) & "\(safeBody)"
                        set body of theNote to newHTML
                    end tell
                end timeout
                return "OK"
            on error errMsg number errNum
                if errNum is -1743 then return "ERR:AUTOMATION_DENIED"
                return "ERR:SCRIPT:" & errNum & ":" & errMsg
            end try
        end run
        """
        let raw = try await run(script: script)
        try Self.assertOk(raw)
    }

    public func createNote(title: String, body: String, timeout: TimeInterval) async throws -> String {
        let safeTitle = escapeForAS(title)
        let safeBody = escapeForAS(NotesHTMLRenderer.render(body))
        let timeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let script = """
        on run
            try
                with timeout of \(timeoutSeconds) seconds
                    tell application "Notes"
                        if not running then return "ERR:NOTES_NOT_RUNNING"
                        set newNote to make new note at default account with properties {name:"\(safeTitle)", body:"\(safeBody)"}
                        return "OK:" & (id of newNote)
                    end tell
                end timeout
            on error errMsg number errNum
                if errNum is -1743 then return "ERR:AUTOMATION_DENIED"
                return "ERR:SCRIPT:" & errNum & ":" & errMsg
            end try
        end run
        """
        let raw = try await run(script: script)
        try Self.assertOk(raw)
        if raw.hasPrefix("OK:") { return String(raw.dropFirst(3)) }
        throw AppleScriptError.scriptFailed(raw)
    }

    private static func assertOk(_ raw: String) throws {
        switch raw {
        case "ERR:NOTES_NOT_RUNNING":  throw AppleScriptError.notesNotRunning
        case "ERR:NO_SELECTION":       throw AppleScriptError.noSelection
        case "ERR:SELECTION_INVALID":  throw AppleScriptError.scriptFailed("selection invalid (Notes 未聚焦窗口)")
        case "ERR:AUTOMATION_DENIED":  throw AppleScriptError.automationDenied
        case "ERR:NOTE_CHANGED":       throw AppleScriptError.noteChanged
        default: break
        }
        if raw.hasPrefix("ERR:SELECTION_CHANGED:") {
            throw AppleScriptError.selectionChanged(String(raw.dropFirst("ERR:SELECTION_CHANGED:".count)))
        }
        if raw.hasPrefix("ERR:SCRIPT:") {
            throw AppleScriptError.scriptFailed(String(raw.dropFirst("ERR:SCRIPT:".count)))
        }
    }

    private func escapeForAS(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        return out
    }

    /// 在当前 App 进程内编译并执行脚本，确保 TCC 与 App Sandbox 按本 App 的签名判定权限。
    private func run(script: String) async throws -> String {
        guard let appleScript = NSAppleScript(source: script) else {
            throw AppleScriptError.scriptFailed("无法创建 AppleScript")
        }

        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "未知错误"
            switch number {
            case -1743:
                throw AppleScriptError.automationDenied
            case -1712:
                throw AppleScriptError.timeout
            default:
                let prefix = number.map { "\($0):" } ?? ""
                throw AppleScriptError.scriptFailed("\(prefix)\(message)")
            }
        }

        return (result.stringValue ?? result.description)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
