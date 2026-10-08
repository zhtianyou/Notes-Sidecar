import Foundation
import CryptoKit

/// 笔记定位器（note.id 是主键，标题/账号/文件夹只用于排错）
public struct NoteLocator: Codable, Hashable, Sendable {
    public let noteId: String
    public var titleSnapshot: String
    public var accountName: String?
    public var folderName: String?
    public var modificationDate: Date

    public init(noteId: String, titleSnapshot: String, accountName: String? = nil, folderName: String? = nil, modificationDate: Date) {
        self.noteId = noteId
        self.titleSnapshot = titleSnapshot
        self.accountName = accountName
        self.folderName = folderName
        self.modificationDate = modificationDate
    }
}

/// 笔记快照（包含解析后的正文 / 修改日期 / 哈希）
public struct NoteContext: Codable, Hashable, Sendable {
    public let locator: NoteLocator
    public let plaintext: String
    public let htmlBody: String?
    public let bodyHash: String
    public let selection: SelectionRange?
    public let attachmentCount: Int
    public let linkCount: Int

    public struct SelectionRange: Codable, Hashable, Sendable {
        public let start: Int
        public let length: Int
        public init(start: Int, length: Int) { self.start = start; self.length = length }
    }

    public init(locator: NoteLocator, plaintext: String, htmlBody: String? = nil, bodyHash: String, selection: SelectionRange? = nil, attachmentCount: Int = 0, linkCount: Int = 0) {
        self.locator = locator
        self.plaintext = plaintext
        self.htmlBody = htmlBody
        self.bodyHash = bodyHash
        self.selection = selection
        self.attachmentCount = attachmentCount
        self.linkCount = linkCount
    }

    public static func hash(plaintext: String) -> String {
        // Swift.Hasher is intentionally randomized between processes and is
        // unsuitable for persisted drift/audit identifiers. Keep a stable
        // 128-bit prefix of SHA-256 instead.
        SHA256.hash(data: Data(plaintext.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func fromPlaintext(locator: NoteLocator, plaintext: String, htmlBody: String? = nil, selection: SelectionRange? = nil, attachmentCount: Int = 0, linkCount: Int = 0) -> NoteContext {
        NoteContext(locator: locator, plaintext: plaintext, htmlBody: htmlBody, bodyHash: hash(plaintext: plaintext), selection: selection, attachmentCount: attachmentCount, linkCount: linkCount)
    }
}

public enum NoteContextChange: Sendable {
    case notesNotRunning
    case noSelection
    case updated(NoteContext)
    case stale(NoteContext, lastSeenHash: String)
    case error(String)
}
