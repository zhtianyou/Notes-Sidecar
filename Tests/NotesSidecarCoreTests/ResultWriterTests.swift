import XCTest
@testable import NotesSidecar

final class ResultWriterTests: XCTestCase {
    func testNotesHTMLRendererFormatsCommonMarkdown() {
        let markdown = """
        # 标题
        **重点**与`代码`

        - 第一项
        - 第二项

        | 项目 | 内容 |
        |---|---|
        | 收款行 | 招商银行 |
        """

        let html = NotesHTMLRenderer.render(markdown)

        XCTAssertTrue(html.contains("<h1>标题</h1>"))
        XCTAssertTrue(html.contains("<strong>重点</strong>"))
        XCTAssertTrue(html.contains("<code>代码</code>"))
        XCTAssertTrue(html.contains("<ul><li>第一项</li><li>第二项</li></ul>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>项目</th>"))
        XCTAssertTrue(html.contains("<td>招商银行</td>"))
    }

    func testNotesHTMLRendererEscapesRawHTML() {
        let html = NotesHTMLRenderer.render("<script>alert('x')</script> & 正文")

        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&amp; 正文"))
    }

    func testSafeAppendWritesWhenSnapshotMatches() async throws {
        let source = makeContext(id: "note-1", title: "项目", body: "原文")
        let notes = MockNotes(context: source)
        let plan = await ResultWriter.shared.makeAppendPlan(
            answer: "结论",
            source: source,
            now: Date(timeIntervalSince1970: 0)
        )

        try await ResultWriter.shared.appendSafely(plan: plan, contextProvider: notes, writer: notes)

        let calls = await notes.appendCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.noteId, "note-1")
        XCTAssertTrue(calls.first?.body.contains("结论") == true)
    }

    func testSafeAppendRejectsChangedBodyWithoutWriting() async throws {
        let source = makeContext(id: "note-1", title: "项目", body: "旧正文")
        let changed = makeContext(id: "note-1", title: "项目", body: "用户刚刚修改的正文")
        let notes = MockNotes(context: changed)
        let plan = await ResultWriter.shared.makeAppendPlan(answer: "结论", source: source)

        do {
            try await ResultWriter.shared.appendSafely(plan: plan, contextProvider: notes, writer: notes)
            XCTFail("正文变化时不应写入")
        } catch let error as ResultWriter.SafeAppendError {
            XCTAssertEqual(error, .noteChanged(title: "项目"))
        }

        let calls = await notes.appendCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testSafeAppendRejectsDifferentSelectedNote() async throws {
        let source = makeContext(id: "note-1", title: "项目 A", body: "正文")
        let selected = makeContext(id: "note-2", title: "项目 B", body: "正文")
        let notes = MockNotes(context: selected)
        let plan = await ResultWriter.shared.makeAppendPlan(answer: "结论", source: source)

        do {
            try await ResultWriter.shared.appendSafely(plan: plan, contextProvider: notes, writer: notes)
            XCTFail("选择变化时不应写入")
        } catch let error as ResultWriter.SafeAppendError {
            XCTAssertEqual(error, .selectionChanged(expectedTitle: "项目 A", actualTitle: "项目 B"))
        }

        let calls = await notes.appendCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testSafeAppendMapsAtomicBodyConflictWithoutWriting() async throws {
        let source = makeContext(id: "note-1", title: "项目", body: "原文")
        let notes = MockNotes(context: source, atomicError: .noteChanged)
        let plan = await ResultWriter.shared.makeAppendPlan(answer: "结论", source: source)

        do {
            try await ResultWriter.shared.appendSafely(plan: plan, contextProvider: notes, writer: notes)
            XCTFail("原子写入阶段发现正文变化时不应写入")
        } catch let error as ResultWriter.SafeAppendError {
            XCTAssertEqual(error, .noteChanged(title: "项目"))
        }

        let calls = await notes.appendCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testSafeAppendMapsAtomicSelectionConflictWithoutWriting() async throws {
        let source = makeContext(id: "note-1", title: "项目 A", body: "原文")
        let notes = MockNotes(context: source, atomicError: .selectionChanged("项目 B"))
        let plan = await ResultWriter.shared.makeAppendPlan(answer: "结论", source: source)

        do {
            try await ResultWriter.shared.appendSafely(plan: plan, contextProvider: notes, writer: notes)
            XCTFail("原子写入阶段发现选择变化时不应写入")
        } catch let error as ResultWriter.SafeAppendError {
            XCTAssertEqual(error, .selectionChanged(expectedTitle: "项目 A", actualTitle: "项目 B"))
        }

        let calls = await notes.appendCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testConflictRebaseThenConfirmWritesOnlyToLatestSnapshot() async throws {
        let original = makeContext(id: "note-1", title: "项目", body: "原始正文")
        let changed = makeContext(id: "note-1", title: "项目", body: "用户已更新的正文")
        let notes = MockNotes(context: changed)
        let firstPlan = await ResultWriter.shared.makeAppendPlan(
            answer: "AI 结论",
            source: original,
            now: Date(timeIntervalSince1970: 0)
        )

        do {
            try await ResultWriter.shared.appendSafely(plan: firstPlan, contextProvider: notes, writer: notes)
            XCTFail("冲突版本绝不能直接写入")
        } catch let error as ResultWriter.SafeAppendError {
            XCTAssertEqual(error, .noteChanged(title: "项目"))
        }
        let rejectedCalls = await notes.appendCalls
        XCTAssertTrue(rejectedCalls.isEmpty)

        let rebased = try await ResultWriter.shared.rebaseAppendPlan(
            firstPlan,
            contextProvider: notes,
            now: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(rebased.id, firstPlan.id)
        XCTAssertEqual(rebased.answer, "AI 结论")
        XCTAssertEqual(rebased.source.bodyHash, changed.bodyHash)

        try await ResultWriter.shared.appendSafely(plan: rebased, contextProvider: notes, writer: notes)
        let calls = await notes.appendCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].body.contains("AI 结论"))
    }

    private func makeContext(id: String, title: String, body: String) -> NoteContext {
        let locator = NoteLocator(
            noteId: id,
            titleSnapshot: title,
            modificationDate: Date(timeIntervalSince1970: 0)
        )
        return NoteContext.fromPlaintext(locator: locator, plaintext: body)
    }
}

private actor MockNotes: NotesContextProviding, NotesWriting {
    struct AppendCall: Sendable {
        let noteId: String
        let body: String
    }

    var context: NoteContext
    let atomicError: BridgeError?
    private(set) var appendCalls: [AppendCall] = []

    init(context: NoteContext, atomicError: BridgeError? = nil) {
        self.context = context
        self.atomicError = atomicError
    }

    func currentContext() async throws -> NoteContext { context }

    func appendToNote(noteId: String, body: String) async throws {
        appendCalls.append(AppendCall(noteId: noteId, body: body))
    }

    func appendToNote(noteId: String, body: String, expectedPlaintext: String) async throws {
        if let atomicError { throw atomicError }
        guard context.locator.noteId == noteId else {
            throw BridgeError.selectionChanged(context.locator.titleSnapshot)
        }
        guard context.plaintext == expectedPlaintext else {
            throw BridgeError.noteChanged
        }
        appendCalls.append(AppendCall(noteId: noteId, body: body))
    }

    func createNote(title: String, body: String) async throws -> String { "new-note" }
}
