import Foundation
import ApplicationServices
import AppKit

public struct CompatibilityProbeReport: Sendable, Hashable {
    public enum Check: String, Sendable, Hashable { case passed, unavailable, failed }
    public let macOSVersion: String; public let notesVersion: String
    public let appleScriptRead: Check; public let attachmentMetadata: Check; public let accessibility: Check
    public let detail: String
    public var summary: String { "macOS \(macOSVersion) · Notes \(notesVersion) · AppleScript \(appleScriptRead.rawValue) · Attachments \(attachmentMetadata.rawValue) · Accessibility \(accessibility.rawValue)" }
}

public enum CompatibilityProbe {
    public static func run(bridge: NotesBridge = .shared) async -> CompatibilityProbeReport {
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        let notesVersion = (NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes").flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }) ?? "not installed"
        let read: CompatibilityProbeReport.Check
        let detail: String
        do { _ = try await bridge.currentContext(); read = .passed; detail = "Current selected note can be read through AppleScript." }
        catch let error as BridgeError {
            switch error {
            case .notesNotRunning, .noSelection, .automationDenied: read = .unavailable
            default: read = .failed
            }
            detail = error.localizedDescription
        }
        catch { read = .failed; detail = error.localizedDescription }
        return CompatibilityProbeReport(macOSVersion: macOS, notesVersion: notesVersion, appleScriptRead: read, attachmentMetadata: read == .passed ? .passed : .unavailable, accessibility: AXIsProcessTrusted() ? .passed : .unavailable, detail: detail)
    }
}

/// Bridge 错误：跟 AppleScript 返回码对齐，方便 UI 显示可恢复指引
public enum BridgeError: Error, LocalizedError, Sendable {
    case notesNotRunning
    case noSelection
    case automationDenied
    case scriptFailed(String)
    case decoding(String)
    case timeout
    case selectionChanged(String)
    case noteChanged

    public var errorDescription: String? {
        switch self {
        case .notesNotRunning:     return SidecarLocalizer.text("Notes 未运行", "Notes is not running")
        case .noSelection:         return SidecarLocalizer.text("Notes 里没有选中笔记", "No note is selected in Notes")
        case .automationDenied:    return SidecarLocalizer.text("系统拒绝了 Notes 自动化权限", "Notes automation permission was denied")
        case .scriptFailed(let s): return SidecarLocalizer.text("AppleScript 失败：\(s)", "AppleScript failed: \(s)")
        case .decoding(let s):     return SidecarLocalizer.text("解码失败：\(s)", "Could not decode the Notes response: \(s)")
        case .timeout:             return SidecarLocalizer.text("读取超时", "Reading timed out")
        case .selectionChanged(let title): return SidecarLocalizer.text("当前选中的笔记已变为「\(title)」", "The selected note changed to “\(title)”")
        case .noteChanged:         return SidecarLocalizer.text("笔记正文已发生变化", "The note content changed")
        }
    }
}

public protocol NotesContextProviding: Sendable {
    func currentContext() async throws -> NoteContext
}

public protocol NotesWriting: Sendable {
    func appendToNote(noteId: String, body: String) async throws
    func appendToNote(noteId: String, body: String, expectedPlaintext: String) async throws
    func createNote(title: String, body: String) async throws -> String
}

/// 默认实现：调 osascript。生产环境可以替换成 XPC/XPC helper / AX helper。
public final class NotesBridge: NotesContextProviding, NotesWriting, @unchecked Sendable {
    public static let shared = NotesBridge()
    private let script = AppleScriptBridge()
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 6) {
        self.timeout = timeout
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    public func currentContext() async throws -> NoteContext {
        do {
            let payload = try await script.readCurrent(timeout: timeout)
            guard let id = payload.id, !id.isEmpty else {
                throw BridgeError.noSelection
            }
            let locator = NoteLocator(
                noteId: id,
                titleSnapshot: payload.title ?? SidecarLocalizer.text("(未命名)", "(Untitled)"),
                modificationDate: parseDate(payload.modDate) ?? Date()
            )
            let plaintext = payload.body ?? ""
            return NoteContext.fromPlaintext(locator: locator, plaintext: plaintext, htmlBody: payload.html)
        } catch let e as AppleScriptError {
            switch e {
            case .notesNotRunning:   throw BridgeError.notesNotRunning
            case .noSelection:       throw BridgeError.noSelection
            case .automationDenied:  throw BridgeError.automationDenied
            case .timeout:           throw BridgeError.timeout
            case .selectionChanged(let title): throw BridgeError.selectionChanged(title)
            case .noteChanged:       throw BridgeError.noteChanged
            case .scriptFailed(let s): throw BridgeError.scriptFailed(s)
            }
        }
    }

    public func appendToNote(noteId: String, body: String) async throws {
        do {
            try await script.appendToNote(noteId: noteId, body: body, timeout: timeout)
        } catch let e as AppleScriptError {
            if case .automationDenied = e { throw BridgeError.automationDenied }
            throw BridgeError.scriptFailed(e.localizedDescription)
        }
    }

    public func appendToNote(noteId: String, body: String, expectedPlaintext: String) async throws {
        do {
            try await script.appendToNote(
                noteId: noteId,
                body: body,
                expectedPlaintext: expectedPlaintext,
                timeout: timeout
            )
        } catch let e as AppleScriptError {
            switch e {
            case .automationDenied:
                throw BridgeError.automationDenied
            case .notesNotRunning:
                throw BridgeError.notesNotRunning
            case .noSelection:
                throw BridgeError.noSelection
            case .selectionChanged(let title):
                throw BridgeError.selectionChanged(title)
            case .noteChanged:
                throw BridgeError.noteChanged
            case .timeout:
                throw BridgeError.timeout
            case .scriptFailed(let message):
                throw BridgeError.scriptFailed(message)
            }
        }
    }

    public func createNote(title: String, body: String) async throws -> String {
        do {
            return try await script.createNote(title: title, body: body, timeout: timeout)
        } catch let e as AppleScriptError {
            if case .automationDenied = e { throw BridgeError.automationDenied }
            throw BridgeError.scriptFailed(e.localizedDescription)
        }
    }
}
