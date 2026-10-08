import Foundation
import Combine

@MainActor
public final class SessionController: ObservableObject {
    public struct ImageContextAttachment: Sendable, Hashable {
        public let fileName: String
        public let safeText: String
        public let excludedLineCount: Int
        public let containsPrivateContent: Bool
    }
    public struct AudioContextAttachment: Sendable, Hashable {
        public let fileName: String
        public let safeText: String
        public let excludedSegmentCount: Int
        public let containsPrivateContent: Bool
    }

    @Published public private(set) var session: NoteSession?
    @Published public private(set) var noteContext: NoteContext?
    @Published public private(set) var profile: ProviderProfile?
    @Published public var draft: String = ""
    @Published public private(set) var imageContextAttachment: ImageContextAttachment?
    @Published public private(set) var audioContextAttachment: AudioContextAttachment?
    @Published public private(set) var privacyNotice: String?

    public let state = ConversationState()

    private let store = ConversationStore.shared
    private let bridge: NotesContextProviding
    private let writer: NotesWriting
    private var genTask: Task<Void, Never>?
    private var activeAssistantTurnId: String?
    private var stopRequested = false
    private var responseLanguageIdentifier = "en"
    private var draftOwnerNoteId: String?
    private var draftSaveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init(bridge: NotesContextProviding = NotesBridge.shared,
                writer: NotesWriting = NotesBridge.shared) {
        self.bridge = bridge
        self.writer = writer

        $draft
            .dropFirst()
            .sink { [weak self] value in
                self?.scheduleDraftSave(value)
            }
            .store(in: &cancellables)
    }

    public func setProfile(_ p: ProviderProfile) {
        self.profile = p
    }

    public func clearProfile() {
        self.profile = nil
    }

    /// The app owns the interface preference; the session uses it only for
    /// transient UI labels. Model answers follow the user's question instead.
    public func setResponseLanguage(identifier: String) {
        responseLanguageIdentifier = identifier
    }

    private var usesSimplifiedChinese: Bool {
        responseLanguageIdentifier.lowercased().hasPrefix("zh")
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        usesSimplifiedChinese ? chinese : english
    }

    /// 从 Store 恢复或创建会话，并把 NoteContext 装上
    public func bind(noteContext: NoteContext, profile: ProviderProfile) async {
        if self.noteContext?.locator.noteId != noteContext.locator.noteId,
           case .generating = state.phase {
            stop()
        }
        await persistCurrentDraft()
        draftSaveTask?.cancel()
        self.noteContext = noteContext
        self.profile = profile
        imageContextAttachment = nil
        audioContextAttachment = nil
        privacyNotice = nil
        draftOwnerNoteId = noteContext.locator.noteId
        draft = await store.loadDraft(forNoteId: noteContext.locator.noteId)

        let existing = try? await store.session(forNoteId: noteContext.locator.noteId)
        if var existing = existing {
            existing.titleSnapshot = noteContext.locator.titleSnapshot
            existing.bodyHash = noteContext.bodyHash
            existing.providerProfileId = profile.id
            existing.updatedAt = Date()
            existing.lastOpenedAt = Date()
            self.session = existing
            try? await store.upsertSession(existing)
        } else {
            let s = NoteSession(
                noteId: noteContext.locator.noteId,
                titleSnapshot: noteContext.locator.titleSnapshot,
                bodyHash: noteContext.bodyHash,
                providerProfileId: profile.id
            )
            self.session = s
            try? await store.upsertSession(s)
        }
        await loadHistory()
    }

    private func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        guard let noteId = draftOwnerNoteId else { return }
        draftSaveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            try? await store.saveDraft(value, forNoteId: noteId)
        }
    }

    private func persistCurrentDraft() async {
        guard let noteId = draftOwnerNoteId else { return }
        try? await store.saveDraft(draft, forNoteId: noteId)
    }

    public func loadHistory() async {
        guard let s = session else { return }
        var turns = (try? await store.loadTurns(sessionId: s.id)) ?? []
        // A process cannot resume an in-flight HTTP stream after relaunch. Mark any
        // persisted placeholder as interrupted so the composer is immediately usable.
        for index in turns.indices where turns[index].status == .pending || turns[index].status == .streaming {
            turns[index].status = .failed
            if turns[index].errorMessage == nil {
                turns[index].errorMessage = ui("上次生成被中断，请重试。", "The previous response was interrupted. Please retry.")
            }
            try? await store.upsertTurn(turns[index])
        }
        let events = await store.loadEvents(sessionId: s.id)
        state.replaceTurns(turns, events: events)
    }

    /// 同一篇笔记正文更新时只替换上下文快照，不重载历史，也不中断正在生成的回答。
    public func updateContextSnapshot(_ context: NoteContext) async {
        guard context.locator.noteId == noteContext?.locator.noteId else { return }
        noteContext = context
        guard var current = session else { return }
        current.titleSnapshot = context.locator.titleSnapshot
        current.bodyHash = context.bodyHash
        current.updatedAt = Date()
        session = current
        try? await store.upsertSession(current)
    }

    public func sendFromDraft() async {
        let raw = draft
        guard !raw.isEmpty else { return }
        await send(userQuestion: raw)
        draft = ""
    }

    public func execute(_ command: SlashCommand) async {
        guard state.phase != .generating else { return }
        await send(userQuestion: "\(command.trigger) \(command.promptHint)")
    }

    public func attachImageContext(_ attachment: ImageContextAttachment) {
        imageContextAttachment = attachment
    }

    public func removeImageContext() {
        imageContextAttachment = nil
    }

    public func attachAudioContext(_ attachment: AudioContextAttachment) { audioContextAttachment = attachment }
    public func removeAudioContext() { audioContextAttachment = nil }

    /// 真正的「发送」。会跑：PromptBuilder → ModelRouter（防火墙 + 出站）→ 流式回到 state。
    public func send(userQuestion: String) async {
        guard let note = noteContext, let profile = profile, let session = session else { return }
        if case .generating = state.phase { return }

        // 1) 写盘：用户 turn
        let slash = SlashCommand.match(userQuestion)
        let trimmed = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageContext = imageContextAttachment?.safeText ?? ""
        let audioContext = audioContextAttachment?.safeText ?? ""
        let userTurn = Turn(sessionId: session.id, role: .user, content: userQuestion, status: .completed)
        try? await store.appendTurn(userTurn)
        state.appendUserTurn(userTurn)

        // 2) 占位 assistant turn
        let assistantTurn = Turn(sessionId: session.id, role: .assistant, content: "", status: .streaming,
                                 basedOnBodyHash: note.bodyHash, model: profile.defaultModel)
        try? await store.appendTurn(assistantTurn)
        state.startAssistantTurn(assistantTurn)

        // 3) 事件：contextRead + promptBuilt
        let ctxEvent = RunEvent(turnId: assistantTurn.id, sequence: 0, type: .contextRead,
                                label: usesSimplifiedChinese
                                    ? "已读取「\(note.locator.titleSnapshot)」· \(note.plaintext.count) 字"
                                    : "Read “\(note.locator.titleSnapshot)” · \(note.plaintext.count) characters",
                                status: .ok, durationMs: 18)
        try? await store.appendEvent(ctxEvent, sessionId: session.id); state.appendEvent(ctxEvent)

        let prompt = PromptBuilder.build(
            noteContext: note,
            history: state.turns,
            userQuestion: trimmed,
            imageContext: imageContext,
            slashCommand: slash
        )
        let initialEvaluation = await SensitiveContentFirewall.shared.evaluate(
            noteText: note.plaintext,
            userQuestion: prompt.outboundQuestion,
            conversationSummary: prompt.summary,
            imageText: imageContext,
            audioTranscript: audioContext,
            requestId: "preview-\(assistantTurn.id)"
        )
        privacyNotice = initialEvaluation.findings.isEmpty
            ? nil
            : ui("检测到隐私内容，相关片段不会提交给 AI", "Private content was detected. Related passages will not be sent to AI.")
        let promptEvent = RunEvent(turnId: assistantTurn.id, sequence: 1, type: .promptBuilt,
                                   label: usesSimplifiedChinese
                                        ? "构建上下文 · \(state.turns.count) 轮对话"
                                        : "Building context · \(state.turns.count) turns",
                                   status: initialEvaluation.failedClosed ? .error : .ok,
                                   redactedSummary: "SafeContext hash \(initialEvaluation.status.manifestHash.prefix(8))",
                                   durationMs: 9)
        try? await store.appendEvent(promptEvent, sessionId: session.id); state.appendEvent(promptEvent)

        // 4) 启动流
        state.phase = .generating
        let requestId = UUID().uuidString
        activeAssistantTurnId = assistantTurn.id
        stopRequested = false
        // `ModelRouter` invokes these callbacks from Sendable contexts. Capture
        // the language decision before crossing that boundary instead of
        // reaching back into this main-actor controller from the callbacks.
        let shouldUseSimplifiedChinese = usesSimplifiedChinese

        genTask?.cancel()
        genTask = Task { [weak self] in
            guard let self = self else { return }
            let startedEvent = RunEvent(turnId: assistantTurn.id, sequence: 3, type: .providerRequest,
                                        label: shouldUseSimplifiedChinese ? "调用 \(profile.name)" : "Calling \(profile.name)",
                                        status: .info,
                                        redactedSummary: "协议：\(profile.kind.displayName)")
            try? await self.store.appendEvent(startedEvent, sessionId: session.id); await MainActor.run { self.state.appendEvent(startedEvent) }

            let firstTokenTs = Date()
            let stats = StreamStats()

            do {
                _ = try await ModelRouter.shared.egress(
                    requestId: requestId,
                    safeContext: SafeContext(
                        noteTextSnapshot: note.plaintext,
                        userQuestion: prompt.outboundQuestion,
                        conversationSummary: prompt.summary,
                        imageTextSnapshot: imageContext,
                        audioTranscriptSnapshot: audioContext,
                        sourceKinds: Set<SafeContext.SafeSourceKind>([.noteText, .userQuestion, .previousTurns])
                            .union(imageContext.isEmpty ? [] : Set([.ocrText]))
                            .union(audioContext.isEmpty ? [] : Set([.audioTranscript])),
                        protectedReason: nil
                    ),
                    profile: profile,
                    systemPrompt: prompt.systemPrompt,
                    onEvent: { [weak self] ev in
                        guard let self = self else { return }
                        switch ev {
                        case .started:
                            break
                        case .token(let s):
                            if stats.markFirstToken() {
                                let firstEvent = RunEvent(turnId: assistantTurn.id, sequence: 4,
                                                          type: .providerFirstToken,
                                                          label: shouldUseSimplifiedChinese
                                                              ? "首字 \(Int(Date().timeIntervalSince(firstTokenTs) * 1000)) ms"
                                                              : "First token \(Int(Date().timeIntervalSince(firstTokenTs) * 1000)) ms",
                                                          status: .ok)
                                try? await self.store.appendEvent(firstEvent, sessionId: session.id)
                                await MainActor.run { self.state.appendEvent(firstEvent) }
                            }
                            await MainActor.run { self.state.appendDelta(s, to: assistantTurn.id) }
                        case .finished(_, let usage):
                            if let u = usage { stats.updateUsage(u) }
                        }
                    },
                    manifestSink: { [weak self] manifest in
                        guard let self else { return }
                        let included = manifest.includedSources
                            .map(\.displayName)
                            .sorted()
                            .joined(separator: "、")
                        let excluded = manifest.excludedSourceKinds
                            .map(\.displayName)
                            .sorted()
                            .joined(separator: "、")
                        let manifestEvent = RunEvent(
                            turnId: assistantTurn.id,
                            sequence: 2,
                            type: .privacyScan,
                            label: shouldUseSimplifiedChinese
                                ? "隐私门已放行 · \(manifest.targetHost)"
                                : "Privacy gate passed · \(manifest.targetHost)",
                            status: .ok,
                            redactedSummary: "hash \(manifest.safeContextHash.prefix(12)) · 包含：\(included.isEmpty ? "无" : included) · 排除：\(excluded.isEmpty ? "无" : excluded) · \(manifest.policyVersion)"
                        )
                        Task {
                            try? await self.store.appendEvent(manifestEvent, sessionId: session.id)
                            await MainActor.run { self.state.appendEvent(manifestEvent) }
                        }
                    }
                )

                let doneEvent = RunEvent(turnId: assistantTurn.id, sequence: 99, type: .completed,
                                         label: self.ui("完成", "Done"), status: .ok,
                                         durationMs: Int(Date().timeIntervalSince(firstTokenTs) * 1000))
                try? await self.store.appendEvent(doneEvent, sessionId: session.id)
                await MainActor.run {
                    self.state.appendEvent(doneEvent)
                    self.state.finalize(turnId: assistantTurn.id, status: .completed,
                                        durationMs: Int(Date().timeIntervalSince(firstTokenTs) * 1000),
                                        usage: stats.usage)
                    self.state.phase = .idle
                    self.activeAssistantTurnId = nil
                }
                let completedTurn = await MainActor.run {
                    self.state.turns.last(where: { $0.id == assistantTurn.id }) ?? assistantTurn
                }
                try? await self.store.upsertTurn(completedTurn)
            } catch {
                if Task.isCancelled || self.stopRequested {
                    return
                }
                let failEvent = RunEvent(turnId: assistantTurn.id, sequence: 99, type: .failed,
                                         label: self.ui("失败 · \(error.localizedDescription)", "Failed · \(error.localizedDescription)"),
                                         status: .error)
                try? await self.store.appendEvent(failEvent, sessionId: session.id)
                await MainActor.run {
                    self.state.appendEvent(failEvent)
                    self.state.finalize(turnId: assistantTurn.id, status: .failed,
                                        durationMs: nil, usage: nil,
                                        errorMessage: error.localizedDescription)
                    self.state.phase = .error(error.localizedDescription)
                    self.activeAssistantTurnId = nil
                }
                let failedTurn = await MainActor.run {
                    self.state.turns.last(where: { $0.id == assistantTurn.id }) ?? assistantTurn
                }
                try? await self.store.upsertTurn(failedTurn)
            }
        }
    }

    public func stop() {
        guard case .generating = state.phase,
              let turnId = activeAssistantTurnId,
              let sessionId = session?.id else { return }
        stopRequested = true
        genTask?.cancel()
        genTask = nil
        let partial = state.turns.first(where: { $0.id == turnId })?.content ?? ""
        let event = RunEvent(
            turnId: turnId,
            sequence: 99,
            type: .cancelled,
            label: partial.isEmpty
                ? ui("已停止", "Stopped")
                : ui("已停止 · 保留 \(partial.count) 字", "Stopped · \(partial.count) characters kept"),
            status: .warning
        )
        state.appendEvent(event)
        state.finalize(turnId: turnId, status: .cancelled, durationMs: nil, usage: nil)
        state.phase = .paused
        activeAssistantTurnId = nil
        let cancelledTurn = state.turns.first(where: { $0.id == turnId })
        Task {
            try? await store.appendEvent(event, sessionId: sessionId)
            if let cancelledTurn { try? await store.upsertTurn(cancelledTurn) }
        }
    }

    public func clearAll() async {
        guard let s = session else { return }
        try? await store.deleteAllTurns(sessionId: s.id)
        try? await store.persistEvents(sessionId: s.id, [])
        state.reset()
        imageContextAttachment = nil
    }

    public func deleteTurn(_ turn: Turn) async {
        guard let current = session else { return }
        try? await store.deleteTurn(sessionId: current.id, turnId: turn.id)
        await loadHistory()
    }

    public func deleteFromTurn(_ turn: Turn) async {
        guard let current = session else { return }
        try? await store.deleteTurns(sessionId: current.id, from: turn.createdAt)
        await loadHistory()
    }

    public func regenerate(from turn: Turn) async {
        guard turn.role == .user, !turn.content.isEmpty else { return }
        let question = turn.content
        await deleteFromTurn(turn)
        await send(userQuestion: question)
    }

    public func retryLastQuestion() async {
        guard let question = state.turns.last(where: { $0.role == .user }) else { return }
        await regenerate(from: question)
    }
}

private final class StreamStats: @unchecked Sendable {
    private let lock = NSLock()
    private var _firstToken = false
    private var _usage = TokenUsage(input: nil, output: nil)
    func markFirstToken() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _firstToken { return false }
        _firstToken = true
        return true
    }
    func updateUsage(_ u: TokenUsage) {
        lock.lock(); defer { lock.unlock() }
        _usage = u
    }
    var usage: TokenUsage {
        lock.lock(); defer { lock.unlock() }
        return _usage
    }
}
