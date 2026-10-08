import Foundation

public actor ConversationStore {
    public static let shared = ConversationStore()

    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.defaultDirectory()
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let app = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = app.appendingPathComponent("NotesSidecar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - sessions

    private func sessionsURL() -> URL { baseDirectory.appendingPathComponent("sessions.json") }
    private func draftsURL() -> URL { baseDirectory.appendingPathComponent("drafts.json") }

    public func loadSessions() async -> [NoteSession] {
        let url = sessionsURL()
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([NoteSession].self, from: data) else { return [] }
        return list
    }

    public func allSessions() async -> [NoteSession] {
        await loadSessions()
    }

    public func session(forNoteId noteId: String) async throws -> NoteSession? {
        let all = await loadSessions()
        return all.first { $0.noteId == noteId }
    }

    public func upsertSession(_ session: NoteSession) async throws {
        var all = await loadSessions()
        if let idx = all.firstIndex(where: { $0.id == session.id }) {
            all[idx] = session
        } else {
            all.append(session)
        }
        let data = try encoder.encode(all)
        try data.write(to: sessionsURL(), options: [.atomic])
    }

    public func deleteSession(_ id: String) async throws {
        var all = await loadSessions()
        let removedNoteId = all.first(where: { $0.id == id })?.noteId
        all.removeAll { $0.id == id }
        let data = try encoder.encode(all)
        try data.write(to: sessionsURL(), options: [.atomic])
        let turnsDir = baseDirectory.appendingPathComponent("turns", isDirectory: true)
        try? FileManager.default.removeItem(at: turnsDir.appendingPathComponent("\(id)/"))
        if let removedNoteId { try await saveDraft("", forNoteId: removedNoteId) }
    }

    public func deleteAllSessions() async throws {
        let turnsDir = baseDirectory.appendingPathComponent("turns", isDirectory: true)
        try? FileManager.default.removeItem(at: turnsDir)
        try? FileManager.default.removeItem(at: sessionsURL())
        try? FileManager.default.removeItem(at: draftsURL())
    }

    // MARK: - per-note drafts

    public func loadDraft(forNoteId noteId: String) async -> String {
        guard let data = try? Data(contentsOf: draftsURL()),
              let drafts = try? decoder.decode([String: String].self, from: data) else { return "" }
        return drafts[noteId] ?? ""
    }

    public func saveDraft(_ draft: String, forNoteId noteId: String) async throws {
        var drafts: [String: String] = [:]
        if let data = try? Data(contentsOf: draftsURL()),
           let stored = try? decoder.decode([String: String].self, from: data) {
            drafts = stored
        }
        if draft.isEmpty {
            drafts.removeValue(forKey: noteId)
        } else {
            drafts[noteId] = draft
        }
        let data = try encoder.encode(drafts)
        try data.write(to: draftsURL(), options: [.atomic])
    }

    // MARK: - turns

    private func turnsDir(sessionId: String) -> URL {
        let d = baseDirectory.appendingPathComponent("turns/\(sessionId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public func appendTurn(_ turn: Turn) async throws {
        let url = turnsDir(sessionId: turn.sessionId).appendingPathComponent("\(turn.id).json")
        let data = try encoder.encode(turn)
        try data.write(to: url, options: [.atomic])
    }

    public func upsertTurn(_ turn: Turn) async throws {
        try await appendTurn(turn)
    }

    public func loadTurns(sessionId: String) async throws -> [Turn] {
        let dir = turnsDir(sessionId: sessionId)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var turns: [Turn] = []
        for u in urls where u.pathExtension == "json" {
            if let data = try? Data(contentsOf: u), let t = try? decoder.decode(Turn.self, from: data) {
                turns.append(t)
            }
        }
        return turns.sorted { $0.createdAt < $1.createdAt }
    }

    public func deleteAllTurns(sessionId: String) async throws {
        let dir = turnsDir(sessionId: sessionId)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for u in urls { try? FileManager.default.removeItem(at: u) }
        let eventsURL = dir.appendingPathComponent("events.json")
        try? FileManager.default.removeItem(at: eventsURL)
    }

    public func deleteTurn(sessionId: String, turnId: String) async throws {
        let url = turnsDir(sessionId: sessionId).appendingPathComponent("\(turnId).json")
        try? FileManager.default.removeItem(at: url)
        let remainingEvents = await loadEvents(sessionId: sessionId).filter { $0.turnId != turnId }
        try await persistEvents(sessionId: sessionId, remainingEvents)
    }

    public func deleteTurns(sessionId: String, from date: Date) async throws {
        let turns = try await loadTurns(sessionId: sessionId)
        let removed = turns.filter { $0.createdAt >= date }
        for turn in removed {
            let url = turnsDir(sessionId: sessionId).appendingPathComponent("\(turn.id).json")
            try? FileManager.default.removeItem(at: url)
        }
        let removedIDs = Set(removed.map(\.id))
        let remainingEvents = await loadEvents(sessionId: sessionId).filter { !removedIDs.contains($0.turnId) }
        try await persistEvents(sessionId: sessionId, remainingEvents)
    }

    public func pruneSessions(olderThan cutoff: Date) async throws {
        let stale = await loadSessions().filter { $0.updatedAt < cutoff }
        for session in stale { try await deleteSession(session.id) }
    }

    // MARK: - events

    public func appendEvent(_ event: RunEvent, sessionId: String) async throws {
        var list = await loadEvents(sessionId: sessionId)
        list.append(event)
        let url = turnsDir(sessionId: sessionId).appendingPathComponent("events.json")
        let data = try encoder.encode(list)
        try data.write(to: url, options: [.atomic])
    }

    public func loadEvents(sessionId: String) async -> [RunEvent] {
        let url = turnsDir(sessionId: sessionId).appendingPathComponent("events.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([RunEvent].self, from: data) else { return [] }
        return list.sorted { $0.sequence < $1.sequence }
    }

    public func persistEvents(sessionId: String, _ events: [RunEvent]) async throws {
        let url = turnsDir(sessionId: sessionId).appendingPathComponent("events.json")
        let data = try encoder.encode(events)
        try data.write(to: url, options: [.atomic])
    }
}
