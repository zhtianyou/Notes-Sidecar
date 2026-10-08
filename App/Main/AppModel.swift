import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import ApplicationServices
import ServiceManagement

@MainActor
private enum LaunchAtLoginService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled, service.status != .enabled { try service.register() }
        if !enabled, service.status == .enabled { try service.unregister() }
    }
}

/// 共享模型层：被 SwiftUI 视图、菜单栏、快捷键、NSPanel 全部消费。
@MainActor
public final class AppModel: ObservableObject {
    public static let shared = AppModel()

    // 来自 Core
    public var session = SessionController()
    public let providers = ProviderStore.shared
    public let bridge: NotesBridge
    public let writer: ResultWriter
    public let router: ModelRouter

    // UI 状态
    @Published public var isPanelVisible: Bool = false
    @Published public var windowMode: WindowMode = .docked
    @Published public var profiles: [ProviderProfile] = []
    @Published public var activeProfile: ProviderProfile?
    @Published public var statusBanner: String? = nil
    @Published public var panelCenter: CGPoint? = nil
    @Published public var pendingAppendPlan: ResultWriter.AppendPlan?
    @Published public var isHistoryPresented = false
    @Published public var isCommandPalettePresented = false
    @Published public var isClearConversationConfirmationPresented = false
    @Published public var autoSwitchNotes = true
    @Published public var followNotesWindow = false
    @Published public var isPinned = true
    @Published public var dockSide: DockSide = .right
    @Published public var appearanceMode: AppearanceMode = .system
    @Published public var interfaceLanguage: InterfaceLanguage = .automatic
    @Published public var closeBehavior: CloseBehavior = .hide
    @Published public var historyRetention: HistoryRetention = .forever
    @Published public var defaultWritebackMode: DefaultWritebackMode = .previewAppend
    @Published public private(set) var launchAtLoginEnabled = false
    @Published public var pendingImageImport: PendingImageImport?
    @Published public var isAnalyzingImage = false
    @Published public var pendingAudioImport: PendingAudioImport?
    @Published public var isTranscribingAudio = false
    @Published public private(set) var compatibilityProbeReport: CompatibilityProbeReport?
    @Published public private(set) var isRunningCompatibilityProbe = false

    private var cancellables: Set<AnyCancellable> = []

    public enum WindowMode: String, CaseIterable, Identifiable {
        case docked, independent, compact
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .docked: return "吸附右侧"
            case .independent: return "独立窗口"
            case .compact: return "紧凑"
            }
        }
        public var defaultSize: CGSize {
            switch self {
            case .docked: return CGSize(width: 420, height: 780)
            case .independent: return CGSize(width: 560, height: 760)
            case .compact: return CGSize(width: 360, height: 520)
            }
        }
    }

    public enum DockSide: String, CaseIterable, Identifiable {
        case left, right
        public var id: String { rawValue }
        public var label: String { self == .right ? "右侧" : "左侧" }
    }

    public enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, dark, light, technology
        public var id: String { rawValue }
        public var label: String {
            switch self { case .system: return "跟随系统"; case .dark: return "深色"; case .light: return "浅色"; case .technology: return "科技" }
        }
        public var colorScheme: ColorScheme? {
            switch self { case .system: return nil; case .dark, .technology: return .dark; case .light: return .light }
        }
        func resolvedTheme(systemScheme: ColorScheme) -> SidecarTheme {
            switch self {
            case .system: return systemScheme == .dark ? .dark : .light
            case .dark: return .dark
            case .light: return .light
            case .technology: return .technology
            }
        }
    }

    public enum InterfaceLanguage: String, CaseIterable, Identifiable {
        case automatic, english, simplifiedChinese

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .automatic: return "自动"
            case .english: return "English"
            case .simplifiedChinese: return "简体中文"
            }
        }

        public static func systemUsesSimplifiedChinese(
            preferredLanguages: [String]? = nil
        ) -> Bool {
            let languages = preferredLanguages ?? systemPreferredLanguages()
            guard let identifier = languages.first else { return false }
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            guard normalized == "zh" || normalized.hasPrefix("zh-") else { return false }
            if normalized.contains("hant") || normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
                return false
            }
            return normalized.contains("hans") || normalized == "zh" ||
                normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg")
        }

        public func resolvedIdentifier(
            preferredLanguages: [String]? = nil
        ) -> String {
            switch self {
            case .automatic:
                return Self.systemUsesSimplifiedChinese(preferredLanguages: preferredLanguages) ? "zh-Hans" : "en"
            case .english:
                return "en"
            case .simplifiedChinese:
                return "zh-Hans"
            }
        }

        /// `Locale.preferredLanguages` can be filtered to the app's development
        /// language during launch. Read the global macOS order first so Automatic
        /// follows the actual system language rather than the bundle fallback.
        private static func systemPreferredLanguages() -> [String] {
            // UserDefaults searches the global registration domain as well and
            // remains available to sandboxed builds.
            if let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
               !languages.isEmpty {
                return languages
            }
            if let languages = UserDefaults.standard
                .persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
               !languages.isEmpty {
                return languages
            }
            let currentIdentifier = Locale.current.identifier
            if !currentIdentifier.isEmpty {
                return [currentIdentifier]
            }
            return Locale.preferredLanguages
        }
    }

    public var interfaceLocale: Locale {
        Locale(identifier: interfaceLanguage.resolvedIdentifier())
    }

    public func localized(_ key: String) -> String {
        let identifier = interfaceLanguage.resolvedIdentifier()
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: interfaceLocale, arguments: arguments)
    }

    /// Runtime text (status banners and AppKit panels) is not automatically
    /// resolved by SwiftUI's locale environment. Keep that path explicit so an
    /// English interface never falls back to an authoring-language string.
    public func interfaceText(_ simplifiedChinese: String, _ english: String) -> String {
        interfaceLanguage.resolvedIdentifier().hasPrefix("zh") ? simplifiedChinese : english
    }

    public enum CloseBehavior: String, CaseIterable, Identifiable {
        case hide, quit
        public var id: String { rawValue }
        public var label: String { self == .hide ? "隐藏边栏" : "退出应用" }
    }

    public enum HistoryRetention: String, CaseIterable, Identifiable {
        case forever, thirtyDays, untilQuit
        public var id: String { rawValue }
        public var label: String {
            switch self { case .forever: return "永久"; case .thirtyDays: return "30 天"; case .untilQuit: return "退出即清空" }
        }
    }

    public enum DefaultWritebackMode: String, CaseIterable, Identifiable {
        case copy, previewAppend, newNote
        public var id: String { rawValue }
        public var label: String {
            switch self { case .copy: return "复制"; case .previewAppend: return "预览后追加"; case .newNote: return "新建笔记" }
        }
    }

    public struct PendingImageImport: Identifiable, Hashable {
        public let id = UUID()
        public let fileName: String
        public let safeText: String
        public let findingLabels: [String]
        public let excludedLineCount: Int
        public let recognizedLineCount: Int
        public let privacyScanFailed: Bool

        public var containsPrivateContent: Bool { !findingLabels.isEmpty || privacyScanFailed }
    }
    public struct PendingAudioImport: Identifiable, Hashable {
        public let id = UUID()
        public let fileName: String
        public let safeText: String
        public let findingLabels: [String]
        public let excludedSegmentCount: Int
        public let segmentCount: Int
        public let privacyScanFailed: Bool
        public var containsPrivateContent: Bool { !findingLabels.isEmpty || privacyScanFailed }
    }

    public init(bridge: NotesBridge = NotesBridge.shared,
                writer: ResultWriter = .shared,
                router: ModelRouter = .shared) {
        self.bridge = bridge
        self.writer = writer
        self.router = router

        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "windowMode"), let value = WindowMode(rawValue: raw) { windowMode = value }
        // One-time migration for builds that shipped the unreliable poller.
        // Re-enable automatic switching once; subsequent user changes remain respected.
        if defaults.bool(forKey: "autoSwitchNotesReliablePollerMigrated") {
            if defaults.object(forKey: "autoSwitchNotes") != nil { autoSwitchNotes = defaults.bool(forKey: "autoSwitchNotes") }
        } else {
            autoSwitchNotes = true
            defaults.set(true, forKey: "autoSwitchNotes")
            defaults.set(true, forKey: "autoSwitchNotesReliablePollerMigrated")
        }
        if defaults.object(forKey: "followNotesWindow") != nil { followNotesWindow = defaults.bool(forKey: "followNotesWindow") }
        // A menu-bar Sidecar has no normal Cmd-Tab entry. Earlier builds left
        // this off, which made the panel look as though it disappeared whenever
        // the user switched apps. Move existing installations to the reliable
        // default once; later changes remain entirely user-controlled.
        if defaults.bool(forKey: "keepSidecarVisibleMigrationV2") {
            if defaults.object(forKey: "isPinned") != nil { isPinned = defaults.bool(forKey: "isPinned") }
        } else {
            isPinned = true
            defaults.set(true, forKey: "isPinned")
            defaults.set(true, forKey: "keepSidecarVisibleMigrationV2")
        }
        if let raw = defaults.string(forKey: "dockSide"), let value = DockSide(rawValue: raw) { dockSide = value }
        if let raw = defaults.string(forKey: "appearanceMode"), let value = AppearanceMode(rawValue: raw) { appearanceMode = value }
        if let raw = defaults.string(forKey: "interfaceLanguage"), let value = InterfaceLanguage(rawValue: raw) { interfaceLanguage = value }
        UserDefaults(suiteName: "group.com.youwin.NotesSidecar")?.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        session.setResponseLanguage(identifier: interfaceLanguage.resolvedIdentifier())
        if let raw = defaults.string(forKey: "closeBehavior"), let value = CloseBehavior(rawValue: raw) { closeBehavior = value }
        if let raw = defaults.string(forKey: "historyRetention"), let value = HistoryRetention(rawValue: raw) { historyRetention = value }
        if let raw = defaults.string(forKey: "defaultWritebackMode"), let value = DefaultWritebackMode(rawValue: raw) { defaultWritebackMode = value }
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled

        // 监听 session.phase，把 Phase 转成 banner
        session.state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self = self else { return }
                switch phase {
                case .idle:
                    // Clear only phase-owned transient text. ContextCoordinator and
                    // model-refresh messages are useful results and must survive an
                    // asynchronous `.idle` publication from history loading.
                    if self.statusBanner == self.localized("正在生成") ||
                        self.statusBanner == self.localized("已暂停") ||
                        self.statusBanner?.hasPrefix(self.interfaceText("第 ", "Retrying")) == true ||
                        self.statusBanner?.hasPrefix(self.interfaceText("错误：", "Error:")) == true {
                        self.statusBanner = nil
                    }
                case .generating: self.statusBanner = self.localized("正在生成")
                case .paused: self.statusBanner = self.localized("已暂停")
                case .retrying(let n): self.statusBanner = self.localizedFormat("第 %lld 次重试中", n)
                case .error(let s): self.statusBanner = self.localizedFormat("错误：%@", s)
                }
            }
            .store(in: &cancellables)
    }

    public func bootstrap() async {
        await SensitiveContentFirewall.shared.load()
        if historyRetention == .thirtyDays,
           let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) {
            try? await ConversationStore.shared.pruneSessions(olderThan: cutoff)
        }
        let storedProfiles = await providers.all()
        // Older builds seeded model names from a bundled catalog. Clear those
        // one time so every built-in Provider starts from the account-specific
        // catalog returned after authorization.
        let defaults = UserDefaults.standard
        let resetLegacyCatalogs = !defaults.bool(forKey: "liveProviderCatalogMigrationV1")
        let ps = storedProfiles.map { stored -> ProviderProfile in
            var upgraded = stored.applyingCompatibilityDefaults()
            if resetLegacyCatalogs,
               upgraded.preset != ProviderPreset.customOpenAI.rawValue {
                upgraded.availableModels = []
                upgraded.defaultModel = ""
            }
            return upgraded
        }
        if resetLegacyCatalogs {
            defaults.set(true, forKey: "liveProviderCatalogMigrationV1")
        }
        for (old, upgraded) in zip(storedProfiles, ps) where old != upgraded {
            try? await providers.upsert(upgraded)
        }
        self.profiles = ps
        let preferredId = UserDefaults.standard.string(forKey: "activeProviderID")
        let selected = ps.first(where: { $0.id == preferredId }) ?? ps.first
        self.activeProfile = selected
        session.setProfile(selected ?? ProviderProfile(
            name: "未配置",
            kind: .openAICompatible,
            capabilities: []
        ))
        ContextCoordinator.shared.start(model: self)
        refreshAuthorizedModelCatalogsInBackground()
        await importPendingShare()
    }

    // MARK: - 暴露给菜单栏 / 快捷键的方法

    /// Settings Scene 的唯一入口。自建 NSPanel 不在 SwiftUI 命令响应链中，
    /// 因此菜单栏、Header 和错误恢复都通过同一通知交给 RootView 的
    /// `openSettings` 环境动作，避免维护第二个设置窗口。
    public func openSettings() {
        NotificationCenter.default.post(name: .notesSidecarOpenSettings, object: nil)
    }

    /// 显式导入图片。原图只交给本机 ImageIO / Vision；弹出确认前不会进入草稿，
    /// 确认后也只加入隐私门放行的文字。
    public func chooseImageForLocalRecognition() async {
        guard !isAnalyzingImage else { return }
        await Task.yield() // 让 SwiftUI Menu 先结束事件追踪，再显示系统面板。
        let panel = NSOpenPanel()
        panel.title = interfaceText("选择要在本机识别的图片", "Choose an image to recognize locally")
        panel.prompt = interfaceText("本机识别", "Recognize Locally")
        panel.message = interfaceText("图片原图不会上传；识别出的隐私内容会在发送给 AI 前排除。", "The original image is not uploaded. Private text is excluded before anything is sent to AI.")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isAnalyzingImage = true
        statusBanner = interfaceText("正在本机识别图片…", "Recognizing image locally…")
        defer { isAnalyzingImage = false }
        do {
            let result = try await LocalImageRecognizer.shared.analyze(url: url)
            pendingImageImport = PendingImageImport(
                fileName: result.fileName,
                safeText: result.safeText,
                findingLabels: Array(Set(result.privacyFindings.map { $0.kind.displayName })).sorted(),
                excludedLineCount: result.excludedLineCount,
                recognizedLineCount: result.recognizedLineCount,
                privacyScanFailed: result.privacyScanFailed
            )
            statusBanner = result.containsPrivateContent
                ? interfaceText("图片识别到隐私内容，等待确认", "Private content was found in the image. Review before continuing.")
                : interfaceText("图片已在本机完成识别", "Image recognized locally")
        } catch {
            statusBanner = interfaceText("图片识别失败：\(error.localizedDescription)", "Image recognition failed: \(error.localizedDescription)")
        }
    }

    public func confirmImageImport(_ candidate: PendingImageImport) {
        guard !candidate.privacyScanFailed, !candidate.safeText.isEmpty else { return }
        session.attachImageContext(.init(
            fileName: candidate.fileName,
            safeText: candidate.safeText,
            excludedLineCount: candidate.excludedLineCount,
            containsPrivateContent: candidate.containsPrivateContent
        ))
        pendingImageImport = nil
        statusBanner = candidate.containsPrivateContent
            ? interfaceText("图片上下文已就绪；隐私部分不会提交给 AI", "Image context is ready. Private content will not be sent to AI.")
            : interfaceText("图片上下文已就绪；原图不会提交给 AI", "Image context is ready. The original image will not be sent to AI.")
    }

    public func cancelImageImport() {
        pendingImageImport = nil
        statusBanner = interfaceText("已取消图片导入", "Image import cancelled")
    }

    /// Audio is always transcribed with the on-device Speech engine. There is
    /// no cloud fallback, and only timestamped segments that pass the firewall
    /// can reach the conversation context.
    public func chooseAudioForLocalTranscription() async {
        guard !isTranscribingAudio else { return }
        await Task.yield()
        let panel = NSOpenPanel()
        panel.title = interfaceText("选择要在本机转写的音频", "Choose audio to transcribe locally")
        panel.prompt = interfaceText("本机转写", "Transcribe Locally")
        panel.message = interfaceText("音频不会上传；带隐私的转写片段会在发送给 AI 前排除。", "Audio is not uploaded. Private transcript segments are excluded before anything is sent to AI.")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isTranscribingAudio = true
        statusBanner = interfaceText("正在本机转写音频…", "Transcribing audio locally…")
        defer { isTranscribingAudio = false }
        do {
            let result = try await LocalAudioTranscriber.shared.transcribe(url: url, locale: interfaceLocale)
            pendingAudioImport = PendingAudioImport(
                fileName: result.fileName,
                safeText: result.safeText,
                findingLabels: Array(Set(result.privacyFindings.map { $0.kind.displayName })).sorted(),
                excludedSegmentCount: result.excludedSegmentCount,
                segmentCount: result.safeSegments.count,
                privacyScanFailed: result.privacyScanFailed
            )
            statusBanner = result.containsPrivateContent
                ? interfaceText("音频识别到隐私内容，等待确认", "Private content was found in the transcript. Review before continuing.")
                : interfaceText("音频已在本机完成转写", "Audio transcribed locally")
        } catch {
            statusBanner = interfaceText("音频转写失败：\(error.localizedDescription)", "Audio transcription failed: \(error.localizedDescription)")
        }
    }

    public func confirmAudioImport(_ candidate: PendingAudioImport) {
        guard !candidate.privacyScanFailed, !candidate.safeText.isEmpty else { return }
        session.attachAudioContext(.init(
            fileName: candidate.fileName,
            safeText: candidate.safeText,
            excludedSegmentCount: candidate.excludedSegmentCount,
            containsPrivateContent: candidate.containsPrivateContent
        ))
        pendingAudioImport = nil
        statusBanner = candidate.containsPrivateContent
            ? interfaceText("音频上下文已就绪；隐私片段不会提交给 AI", "Audio context is ready. Private segments will not be sent to AI.")
            : interfaceText("音频上下文已就绪；原始音频不会提交给 AI", "Audio context is ready. The original audio will not be sent to AI.")
    }

    public func cancelAudioImport() {
        pendingAudioImport = nil
        statusBanner = interfaceText("已取消音频导入", "Audio import cancelled")
    }

    public func togglePanelVisibility() {
        if isPanelVisible {
            isPanelVisible = false
            SidecarPanelController.shared.syncVisibility()
        } else {
            showPanel()
        }
    }

    /// Explicit presentation (menu bar, reopen, etc.) is intentionally
    /// different from toggling: it must reveal an already-visible panel that
    /// is currently covered by another app.
    public func showPanel() {
        isPanelVisible = true
        SidecarPanelController.shared.syncVisibility(bringToFront: true)
    }

    public func openCommandPalette() {
        showPanel()
        isCommandPalettePresented = true
    }

    public func togglePinned() {
        isPinned.toggle()
        updatePreferences()
        SidecarPanelController.shared.applyPinnedState()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            statusBanner = launchAtLoginEnabled
                ? localized("已启用开机启动")
                : localized("已关闭开机启动")
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            statusBanner = localizedFormat("开机启动设置失败：%@", error.localizedDescription)
        }
    }

    public func sendFromMenu() async {
        await session.sendFromDraft()
    }

    public func stopFromMenu() {
        session.stop()
    }

    public func copyLastAnswer() {
        guard let last = session.state.lastAnswer as String?, !last.isEmpty else { return }
        copyAnswer(last)
    }

    public func copyAnswer(_ answer: String) {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        statusBanner = interfaceText("已复制回答", "Response copied")
    }

    public func appendLastAnswer() async {
        guard let note = session.noteContext?.locator else { return }
        guard let last = session.state.turns.last(where: { $0.role == .assistant })?.content, !last.isEmpty else { return }
        await appendAnswer(last, to: note)
    }

    public func performDefaultWriteback() async {
        guard let answer = session.state.turns.last(where: { $0.role == .assistant })?.content,
              !answer.isEmpty else {
            statusBanner = interfaceText("还没有可写回的回答", "There is no response to write back yet")
            return
        }
        switch defaultWritebackMode {
        case .copy:
            copyAnswer(answer)
        case .previewAppend:
            await appendAnswer(answer)
        case .newNote:
            await createNote(from: answer)
        }
    }

    public func appendAnswer(_ answer: String, to note: NoteLocator? = nil) async {
        guard !answer.isEmpty, let context = session.noteContext else { return }
        if let note, note.noteId != context.locator.noteId {
            statusBanner = interfaceText("目标笔记已切换，请重新打开对应会话", "The target note changed. Reopen its conversation before writing back.")
            return
        }
        pendingAppendPlan = await writer.makeAppendPlan(answer: answer, source: context)
    }

    public func confirmAppend(_ plan: ResultWriter.AppendPlan) async throws {
        try await writer.appendSafely(plan: plan, contextProvider: bridge, writer: bridge)
        pendingAppendPlan = nil
        statusBanner = interfaceText("已追加到「\(plan.source.locator.titleSnapshot)」", "Appended to “\(plan.source.locator.titleSnapshot)”")

        if let profile = activeProfile, let refreshed = try? await bridge.currentContext(),
           refreshed.locator.noteId == plan.source.locator.noteId {
            await session.bind(noteContext: refreshed, profile: profile)
            ContextCoordinator.shared.resetBaseline(refreshed)
        }
    }

    public func rebaseAppendPlan(_ plan: ResultWriter.AppendPlan) async throws {
        pendingAppendPlan = try await writer.rebaseAppendPlan(plan, contextProvider: bridge)
    }

    public func cancelAppend() {
        pendingAppendPlan = nil
    }

    public func createNote(from answer: String) async {
        guard !answer.isEmpty else { return }
        do {
            let preview = await ResultWriter.shared.buildPreview(
                answer: answer,
                mode: .newNote,
                noteTitle: session.noteContext?.locator.titleSnapshot
            )
            _ = try await bridge.createNote(title: preview.title, body: preview.body)
            statusBanner = interfaceText("已新建备忘录", "New note created")
        } catch {
            statusBanner = interfaceText("新建失败：\(error.localizedDescription)", "Could not create note: \(error.localizedDescription)")
        }
    }

    public func clearCurrentConversation() async {
        await session.clearAll()
        statusBanner = interfaceText("已清空当前对话；备忘录内容未改变", "Current conversation cleared. The original note was not changed.")
    }

    public func exportCurrentConversation() {
        guard let note = session.noteContext, !session.state.turns.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = interfaceText("导出当前对话", "Export Current Conversation")
        panel.nameFieldStringValue = safeExportFilename(note.locator.titleSnapshot) + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let body = conversationMarkdown(title: note.locator.titleSnapshot, turns: session.state.turns)
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            statusBanner = interfaceText("已导出当前对话", "Current conversation exported")
        } catch {
            statusBanner = interfaceText("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
        }
    }

    private func conversationMarkdown(title: String, turns: [Turn]) -> String {
        var lines = ["# \(title)", "", "> 由 Notes Sidecar 从本机对话历史导出。", ""]
        for turn in turns where turn.role != .system {
            lines.append("## \(turn.role.displayLabel)")
            lines.append("")
            lines.append(turn.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func safeExportFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? interfaceText("Notes Sidecar 对话", "Notes Sidecar Conversation") : cleaned
    }

    public func refreshContext() async {
        do {
            let ctx = try await bridge.currentContext()
            if let p = activeProfile { await session.bind(noteContext: ctx, profile: p) }
            ContextCoordinator.shared.resetBaseline(ctx)
            statusBanner = interfaceText("已同步「\(ctx.locator.titleSnapshot)」", "Synced “\(ctx.locator.titleSnapshot)”")
        } catch let e as BridgeError {
            switch e {
            case .notesNotRunning: statusBanner = interfaceText("Notes 未运行", "Notes is not running")
            case .noSelection:     statusBanner = interfaceText("未选中笔记", "No note is selected")
            case .automationDenied: statusBanner = interfaceText("AppleEvents 权限被拒绝，请在系统设置授权", "Apple Events permission was denied. Allow it in System Settings.")
            case .timeout:         statusBanner = interfaceText("读取超时", "Reading timed out")
            default:               statusBanner = e.localizedDescription
            }
        } catch {
            statusBanner = interfaceText("读取失败：\(error.localizedDescription)", "Could not read the note: \(error.localizedDescription)")
        }
    }

    public func usePastedContext(title: String, text: String) async {
        guard let profile = activeProfile else {
            statusBanner = interfaceText("请先配置模型服务商", "Set up a model provider first")
            return
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let locator = NoteLocator(
            noteId: "manual:\(UUID().uuidString)",
            titleSnapshot: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "粘贴的内容" : title,
            folderName: "受限模式",
            modificationDate: Date()
        )
        await session.bind(noteContext: .fromPlaintext(locator: locator, plaintext: cleaned), profile: profile)
        ContextCoordinator.shared.resetBaseline(nil)
        statusBanner = interfaceText("受限模式 · 内容仅保存在 Sidecar", "Restricted mode · Content is stored only in Sidecar")
    }

    public func importPendingShare() async {
        guard activeProfile != nil,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.youwin.NotesSidecar") else { return }
        let inbox = container.appendingPathComponent("ShareInbox", isDirectory: true)
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let url = urls.first,
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(ShareInboxPayload.self, from: data) else { return }
        await usePastedContext(title: payload.title, text: payload.text)
        try? FileManager.default.removeItem(at: url)
        isPanelVisible = true
        SidecarPanelController.shared.syncVisibility()
    }

    public var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    public func requestAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func runCompatibilityProbe() async {
        guard !isRunningCompatibilityProbe else { return }
        isRunningCompatibilityProbe = true
        defer { isRunningCompatibilityProbe = false }
        compatibilityProbeReport = await CompatibilityProbe.run(bridge: bridge)
    }

    public func exportAllConversations() {
        let panel = NSSavePanel()
        panel.title = interfaceText("导出全部 Sidecar 对话", "Export All Sidecar Conversations")
        panel.nameFieldStringValue = interfaceText("Notes Sidecar 全部对话.md", "Notes Sidecar Conversations.md")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let targetURL = url

        statusBanner = interfaceText("正在导出全部对话…", "Exporting all conversations…")
        Task {
            do {
                let sessions = await ConversationStore.shared.allSessions().sorted { $0.updatedAt > $1.updatedAt }
                let exportTitle = interfaceText("Notes Sidecar 全部对话", "Notes Sidecar Conversations")
                let exportDescription = interfaceText("从本机历史导出，不包含 API Key。", "Exported from local history. API keys are not included.")
                var sections: [String] = ["# \(exportTitle)", "", "> \(exportDescription)", ""]
                for item in sessions {
                    let turns = (try? await ConversationStore.shared.loadTurns(sessionId: item.id)) ?? []
                    sections.append("# \(item.titleSnapshot)")
                    sections.append("")
                    sections.append(conversationMarkdown(title: item.titleSnapshot, turns: turns))
                }
                try sections.joined(separator: "\n").write(to: targetURL, atomically: true, encoding: .utf8)
                statusBanner = interfaceText("已导出全部对话 · \(sessions.count) 篇 · \(targetURL.lastPathComponent)", "Exported \(sessions.count) conversations · \(targetURL.lastPathComponent)")
            } catch {
                statusBanner = interfaceText("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
            }
        }
    }

    public func clearAllConversationData() async {
        try? await ConversationStore.shared.deleteAllSessions()
        session.state.reset()
        statusBanner = interfaceText("已清空 Sidecar 对话；Notes 和钥匙串未改变", "Sidecar conversations cleared. Notes and Keychain were not changed.")
    }

    public func setProfile(_ p: ProviderProfile) async {
        self.activeProfile = p
        session.setProfile(p)
        UserDefaults.standard.set(p.id, forKey: "activeProviderID")
        _ = await refreshModelCatalog(for: p)
    }

    public func deleteProfile(_ profile: ProviderProfile) async {
        do {
            try await providers.delete(profile.id)
            profiles = await providers.all()
            guard activeProfile?.id == profile.id else { return }
            if let next = profiles.first {
                await setProfile(next)
                statusBanner = interfaceText("已切换到「\(next.name)」", "Switched to “\(next.name)” ")
            } else {
                activeProfile = nil
                session.clearProfile()
                UserDefaults.standard.removeObject(forKey: "activeProviderID")
                statusBanner = interfaceText("服务商已删除，请添加一个模型服务", "Provider deleted. Add a model provider to continue.")
            }
        } catch {
            statusBanner = interfaceText("删除服务商失败：\(error.localizedDescription)", "Could not delete provider: \(error.localizedDescription)")
        }
    }

    public func updatePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(windowMode.rawValue, forKey: "windowMode")
        defaults.set(autoSwitchNotes, forKey: "autoSwitchNotes")
        defaults.set(followNotesWindow, forKey: "followNotesWindow")
        defaults.set(isPinned, forKey: "isPinned")
        defaults.set(dockSide.rawValue, forKey: "dockSide")
        defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
        defaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        UserDefaults(suiteName: "group.com.youwin.NotesSidecar")?.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        defaults.set(closeBehavior.rawValue, forKey: "closeBehavior")
        defaults.set(historyRetention.rawValue, forKey: "historyRetention")
        defaults.set(defaultWritebackMode.rawValue, forKey: "defaultWritebackMode")
        defaults.synchronize()
        session.setResponseLanguage(identifier: interfaceLanguage.resolvedIdentifier())
        MenuBarController.shared.refreshLocalizedMenu()
        SidecarPanelController.shared.preferencesDidChange()
    }

    public func recordProviderTest(_ result: ProviderTestRunner.Result, for profile: ProviderProfile) async {
        var updated = profile
        switch result.httpStatus {
        case .some(let code) where (200..<300).contains(code): updated.lastTestStatus = .connected(Date())
        case 401, 403: updated.lastTestStatus = .authFailed("服务商拒绝了当前密钥")
        case 429: updated.lastTestStatus = .rateLimited(Date())
        case .some(let code): updated.lastTestStatus = .unsupported("HTTP \(code)")
        case .none: updated.lastTestStatus = .networkFailed(result.rawError ?? result.statusLabel)
        }
        if result.httpStatus.map({ (200..<300).contains($0) }) == true {
            var seen = Set<String>()
            updated.availableModels = result.models.filter { seen.insert($0).inserted }
            if !updated.availableModels.contains(updated.defaultModel) {
                updated.defaultModel = updated.availableModels.first ?? updated.defaultModel
            }
        }
        try? await providers.upsert(updated)
        profiles = await providers.all()
        if activeProfile?.id == updated.id {
            activeProfile = updated
            session.setProfile(updated)
        }
    }

    /// ComposerView 切换模型 → 立刻写到 active profile 并持久化
    public func setDefaultModel(_ model: String) {
        guard var p = activeProfile else { return }
        p.defaultModel = model
        activeProfile = p
        session.setProfile(p)
        Task { try? await providers.upsert(p) }
    }

    public func setReasoningEffort(_ effort: ReasoningEffort) {
        guard var p = activeProfile else { return }
        p.reasoningEffort = effort
        activeProfile = p
        session.setProfile(p)
        Task { try? await providers.upsert(p) }
    }

    /// ComposerView / ProviderEditor 拉取服务商可用模型。成功响应替换旧目录，
    /// 避免已退休模型永久残留。
    @Published public var isFetchingModels = false
    @Published public private(set) var refreshingProviderIDs: Set<String> = []

    public func isRefreshingModelCatalog(for profileID: String) -> Bool {
        refreshingProviderIDs.contains(profileID)
    }

    public func fetchAvailableModels() async {
        guard let p = activeProfile else {
            statusBanner = interfaceText("请先选择一个服务商", "Choose a provider first")
            return
        }
        isFetchingModels = true
        defer { isFetchingModels = false }
        let refreshed = await refreshModelCatalog(for: p)
        guard refreshed else {
            statusBanner = interfaceText("服务端未返回模型目录。请确认授权、API Key 与 URL，或手动输入模型 ID。", "The provider returned no model catalog. Check authorization, the API key, and URL, or enter a model ID manually.")
            return
        }
        let count = activeProfile?.availableModels.count ?? 0
        statusBanner = interfaceText("已刷新 · \(count) 个模型", "Refreshed · \(count) models")
    }

    /// Replaces a Provider catalog only with a successful, non-empty live
    /// response. It never falls back to a bundled model list.
    @discardableResult
    public func refreshModelCatalog(for profile: ProviderProfile) async -> Bool {
        guard !refreshingProviderIDs.contains(profile.id) else { return false }
        guard await hasRefreshCredential(for: profile) else { return false }
        refreshingProviderIDs.insert(profile.id)
        defer { refreshingProviderIDs.remove(profile.id) }

        let key = (try? await KeychainStore.shared.readString(ref: profile.keychainCredentialRef)) ?? ""
        let models = await ProviderTestRunner.fetchModelsAsync(profile: profile, key: key)
        var seen = Set<String>()
        let refreshed = models.filter { seen.insert($0).inserted }
        guard !refreshed.isEmpty else { return false }

        var updated = profiles.first(where: { $0.id == profile.id }) ?? profile
        updated.availableModels = refreshed
        if !refreshed.contains(updated.defaultModel) {
            updated.defaultModel = refreshed.first ?? ""
        }
        try? await providers.upsert(updated)
        profiles = await providers.all()
        if activeProfile?.id == updated.id {
            activeProfile = updated
            session.setProfile(updated)
        }
        return true
    }

    private func hasRefreshCredential(for profile: ProviderProfile) async -> Bool {
        if profile.isLocal { return true }
        if profile.preset == ProviderPreset.openai.rawValue,
           profile.authenticationMode == .chatGPTSubscription {
            return await OpenAIChatGPTAuth.shared.isConnected(profile: profile)
        }
        return !((try? await KeychainStore.shared.readString(ref: profile.keychainCredentialRef)) ?? "").isEmpty
    }

    private func refreshAuthorizedModelCatalogsInBackground() {
        let activeID = activeProfile?.id
        let profilesToRefresh = profiles.sorted { lhs, rhs in
            lhs.id == activeID && rhs.id != activeID
        }
        Task { [weak self] in
            guard let self else { return }
            for profile in profilesToRefresh {
                _ = await self.refreshModelCatalog(for: profile)
            }
        }
    }

    public func upsertProfile(_ p: ProviderProfile, apiKey: String?) async throws {
        let normalized = p.applyingCompatibilityDefaults()
        try await providers.upsert(normalized)
        if let key = apiKey, !key.isEmpty {
            try await providers.saveCredential(normalized, key: key)
        }
        let all = await providers.all()
        self.profiles = all
        if activeProfile == nil || activeProfile?.id == normalized.id {
            self.activeProfile = normalized
            session.setProfile(normalized)
            UserDefaults.standard.set(normalized.id, forKey: "activeProviderID")
        }
        await importPendingShare()
    }
}

private struct ShareInboxPayload: Codable {
    let id: UUID
    let title: String
    let text: String
    let createdAt: Date
}
