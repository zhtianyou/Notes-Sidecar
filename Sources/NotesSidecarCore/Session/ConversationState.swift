import Foundation
import Combine

@MainActor
public final class ConversationState: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case generating
        case paused
        case retrying(Int)
        case error(String)
    }

    @Published public private(set) var turns: [Turn] = []
    @Published public private(set) var events: [RunEvent] = []
    @Published public var phase: Phase = .idle
    @Published public private(set) var lastPromptSnapshot: String?
    @Published public private(set) var lastAnswer: String = ""

    public var currentErrorMessage: String? {
        if case .error(let message) = phase, !message.isEmpty { return message }
        guard let latestAssistant = turns.last(where: { $0.role == .assistant }),
              latestAssistant.status == .failed else { return nil }
        return latestAssistant.errorMessage
    }

    public init() {}

    public func appendUserTurn(_ turn: Turn) {
        turns.append(turn)
    }

    public func startAssistantTurn(_ turn: Turn) {
        turns.append(turn)
    }

    public func appendDelta(_ delta: String, to turnId: String) {
        guard let idx = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turns[idx].content += delta
        lastAnswer = turns[idx].content
    }

    public func finalize(turnId: String, status: TurnStatus, durationMs: Int?, usage: TokenUsage?, errorMessage: String? = nil) {
        guard let idx = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turns[idx].status = status
        turns[idx].durationMs = durationMs
        turns[idx].inputTokens = usage?.inputTokens
        turns[idx].outputTokens = usage?.outputTokens
        turns[idx].errorMessage = errorMessage
    }

    public func appendEvent(_ ev: RunEvent) {
        events.append(ev)
    }

    public func reset() {
        turns.removeAll()
        events.removeAll()
        lastAnswer = ""
        phase = .idle
    }

    public func replaceTurns(_ list: [Turn], events: [RunEvent]) {
        self.turns = list
        self.events = events
        self.lastAnswer = list.last(where: { $0.role == .assistant })?.content ?? ""
        self.phase = .idle
    }
}
