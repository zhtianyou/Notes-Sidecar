import XCTest
@testable import NotesSidecar

final class ConversationStoreTests: XCTestCase {
    func testDraftsAreStoredIndependentlyPerNote() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSidecar-DraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(baseDirectory: directory)

        try await store.saveDraft("A 的问题", forNoteId: "note-a")
        try await store.saveDraft("B 的问题", forNoteId: "note-b")

        let draftA = await store.loadDraft(forNoteId: "note-a")
        let draftB = await store.loadDraft(forNoteId: "note-b")
        XCTAssertEqual(draftA, "A 的问题")
        XCTAssertEqual(draftB, "B 的问题")
    }

    func testSavingEmptyDraftRemovesOnlyCurrentNoteDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSidecar-DraftRemovalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(baseDirectory: directory)

        try await store.saveDraft("A", forNoteId: "note-a")
        try await store.saveDraft("B", forNoteId: "note-b")
        try await store.saveDraft("", forNoteId: "note-a")

        let draftA = await store.loadDraft(forNoteId: "note-a")
        let draftB = await store.loadDraft(forNoteId: "note-b")
        XCTAssertEqual(draftA, "")
        XCTAssertEqual(draftB, "B")
    }

    func testAppendEventPreservesEarlierEventsInSameSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSidecar-ConversationStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConversationStore(baseDirectory: directory)
        let sessionId = "session-1"
        let turnId = "turn-1"
        let first = RunEvent(turnId: turnId, sequence: 0, type: .contextRead, label: "读取笔记", status: .ok)
        let second = RunEvent(turnId: turnId, sequence: 1, type: .promptBuilt, label: "构建上下文", status: .ok)

        try await store.appendEvent(first, sessionId: sessionId)
        try await store.appendEvent(second, sessionId: sessionId)

        let loaded = await store.loadEvents(sessionId: sessionId)
        XCTAssertEqual(loaded.map(\.label), ["读取笔记", "构建上下文"])
    }

    func testDeleteTurnAlsoRemovesItsRunEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSidecar-DeleteTurnTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(baseDirectory: directory)
        let turn = Turn(sessionId: "s", role: .assistant, content: "answer", status: .completed)
        try await store.appendTurn(turn)
        try await store.appendEvent(RunEvent(turnId: turn.id, sequence: 0, type: .completed, label: "done"), sessionId: "s")

        try await store.deleteTurn(sessionId: "s", turnId: turn.id)

        let turns = try await store.loadTurns(sessionId: "s")
        let events = await store.loadEvents(sessionId: "s")
        XCTAssertTrue(turns.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    func testDeleteTurnsFromDateKeepsEarlierHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSidecar-DeleteRangeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(baseDirectory: directory)
        let earlier = Turn(sessionId: "s", role: .user, content: "keep", status: .completed, createdAt: Date(timeIntervalSince1970: 100))
        let later = Turn(sessionId: "s", role: .assistant, content: "remove", status: .completed, createdAt: Date(timeIntervalSince1970: 200))
        try await store.appendTurn(earlier)
        try await store.appendTurn(later)

        try await store.deleteTurns(sessionId: "s", from: Date(timeIntervalSince1970: 150))

        let turns = try await store.loadTurns(sessionId: "s")
        XCTAssertEqual(turns.map(\.content), ["keep"])
    }
}
