import Foundation

public enum RunEventType: String, Codable, Sendable {
    case contextRead
    case attachmentsEnumerated
    case localExtraction
    case privacyScan
    case taxonomyUpdated
    case promptBuilt
    case providerRequest
    case providerFirstToken
    case toolStarted
    case toolFinished
    case usage
    case retry
    case completed
    case failed
    case cancelled

    public var iconSystemName: String {
        switch self {
        case .contextRead:           return "doc.text.magnifyingglass"
        case .attachmentsEnumerated: return "paperclip"
        case .localExtraction:       return "rectangle.stack.badge.person.crop"
        case .privacyScan:           return "lock.shield"
        case .taxonomyUpdated:        return "tag"
        case .promptBuilt:           return "text.bubble"
        case .providerRequest:       return "arrow.up.forward.app"
        case .providerFirstToken:    return "bolt.fill"
        case .toolStarted:           return "wrench.and.screwdriver"
        case .toolFinished:          return "checkmark.seal"
        case .usage:                 return "number"
        case .retry:                 return "arrow.clockwise"
        case .completed:             return "checkmark.circle.fill"
        case .failed:                return "exclamationmark.triangle.fill"
        case .cancelled:             return "stop.circle.fill"
        }
    }
}

public enum RunEventStatus: String, Codable, Sendable { case running, ok, warning, error, info }

public struct RunEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let turnId: String
    public let sequence: Int
    public let type: RunEventType
    public let label: String
    public let status: RunEventStatus
    public let redactedSummary: String?
    public let durationMs: Int?
    public let createdAt: Date

    public init(id: String = UUID().uuidString,
                turnId: String,
                sequence: Int,
                type: RunEventType,
                label: String,
                status: RunEventStatus = .info,
                redactedSummary: String? = nil,
                durationMs: Int? = nil,
                createdAt: Date = .init()) {
        self.id = id
        self.turnId = turnId
        self.sequence = sequence
        self.type = type
        self.label = label
        self.status = status
        self.redactedSummary = redactedSummary
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}