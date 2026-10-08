import Foundation

public struct NoteSession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let noteId: String
    public var titleSnapshot: String
    public var bodyHash: String
    public var providerProfileId: String
    public var modelOverride: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date

    public init(id: String = UUID().uuidString,
                noteId: String,
                titleSnapshot: String,
                bodyHash: String,
                providerProfileId: String,
                modelOverride: String? = nil,
                createdAt: Date = .init()) {
        self.id = id
        self.noteId = noteId
        self.titleSnapshot = titleSnapshot
        self.bodyHash = bodyHash
        self.providerProfileId = providerProfileId
        self.modelOverride = modelOverride
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastOpenedAt = createdAt
    }
}

public enum TurnRole: String, Codable, Sendable { case user, assistant, system
    public var displayLabel: String {
        switch self {
        case .user: return SidecarLocalizer.text("你", "You")
        case .assistant: return "AI"
        case .system: return SidecarLocalizer.text("系统", "System")
        }
    }
}

public enum TurnStatus: String, Codable, Sendable { case pending, streaming, completed, cancelled, failed }

public struct Turn: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let sessionId: String
    public var role: TurnRole
    public var content: String
    public var status: TurnStatus
    public var basedOnBodyHash: String?
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var durationMs: Int?
    public var errorMessage: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                sessionId: String,
                role: TurnRole,
                content: String = "",
                status: TurnStatus = .pending,
                basedOnBodyHash: String? = nil,
                model: String? = nil,
                createdAt: Date = .init()) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.status = status
        self.basedOnBodyHash = basedOnBodyHash
        self.model = model
        self.createdAt = createdAt
    }
}
