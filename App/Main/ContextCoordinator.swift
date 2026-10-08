import Foundation
import AppKit
import Combine

/// 笔记切换自动同步：面板可见时定时轮询 NotesBridge 看选中笔记是否变了；
/// 变了就重新 bind，让侧栏无缝切到新对话。
@MainActor
public final class ContextCoordinator: ObservableObject {
    public static let shared = ContextCoordinator()

    private var timerCancellable: AnyCancellable?
    private var lastNoteId: String?
    private var lastBodyHash: String?
    private var lastCharacterCount: Int?
    private var pollInFlight = false
    private weak var model: AppModel?

    private init() {}

    public func start(model: AppModel) {
        self.model = model
        guard timerCancellable == nil else { return }
        // A main-run-loop timer remains alive independently of the bootstrap
        // task that starts it. The previous child Task could silently stop
        // after launch, leaving the visible panel permanently on the old note.
        timerCancellable = Timer.publish(every: 0.7, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.tick() }
            }
        Task { await tick() }
    }

    public func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        lastNoteId = nil
        lastBodyHash = nil
        lastCharacterCount = nil
        pollInFlight = false
    }

    /// 外部强制重置（比如用户点了「读当前笔记」按钮），下一轮 tick 不再依赖缓存。
    public func resetBaseline(_ context: NoteContext?) {
        lastNoteId = context?.locator.noteId
        lastBodyHash = context?.bodyHash
        lastCharacterCount = context?.plaintext.count
    }

    private func tick() async {
        guard !pollInFlight else { return }
        pollInFlight = true
        defer { pollInFlight = false }

        guard let model = model else { return }
        // 仅在侧栏可见时同步；不打扰后台会话
        guard model.isPanelVisible else { return }
        guard model.autoSwitchNotes else { return }
        // A pasted/Shared context is an explicit isolated session. Do not let
        // the background Notes poll replace it; the user can leave it by using
        // “刷新当前笔记” / “测试读取”.
        guard model.session.noteContext?.locator.noteId.hasPrefix("manual:") != true else { return }
        do {
            // Use the model's context source so manual refresh and automatic
            // switching always observe the same Notes bridge instance.
            let ctx = try await model.bridge.currentContext()
            // The visible session is the source of truth. Advancing only the
            // private baseline before a profile existed could leave the UI on
            // the old note forever while the poller believed it had switched.
            if ctx.locator.noteId != model.session.noteContext?.locator.noteId {
                guard let profile = model.activeProfile else { return }
                await model.session.bind(noteContext: ctx, profile: profile)
                lastNoteId = ctx.locator.noteId
                lastBodyHash = ctx.bodyHash
                lastCharacterCount = ctx.plaintext.count
                model.statusBanner = model.localizedFormat("已切换到「%@」", ctx.locator.titleSnapshot)
            } else if ctx.bodyHash != lastBodyHash {
                let previousCount = lastCharacterCount ?? ctx.plaintext.count
                let delta = ctx.plaintext.count - previousCount
                lastBodyHash = ctx.bodyHash
                lastCharacterCount = ctx.plaintext.count
                await model.session.updateContextSnapshot(ctx)
                let change = delta == 0
                    ? model.localized("内容有修改")
                    : model.localizedFormat("%@%lld 字", delta > 0 ? "+" : "", delta)
                model.statusBanner = model.localizedFormat("笔记已更新 %@，将用于下一次提问", change)
            }
        } catch let e as BridgeError {
            switch e {
            case .noSelection, .notesNotRunning:
                // 静默忽略：用户可能根本没开 Notes
                break
            case .timeout, .scriptFailed:
                // 不刷 banner，太吵
                break
            default:
                break
            }
        } catch {
            // 静默
        }
    }
}
