import SwiftUI
import AppKit

private struct AudioPrivacyPreviewView: View {
    @ObservedObject var model: AppModel; let candidate: AppModel.PendingAudioImport
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本地音频转写").font(.title2.bold())
            Text(model.interfaceText("\(candidate.fileName) · \(candidate.segmentCount) 个带时间戳的安全片段", "\(candidate.fileName) · \(candidate.segmentCount) timestamped safe segments"))
                .foregroundStyle(.secondary)
            Label(model.interfaceText(
                candidate.containsPrivateContent ? "识别到隐私内容；相关片段不会提交给 AI。" : "原始音频不会提交给 AI。",
                candidate.containsPrivateContent ? "Private content was detected; related segments will not be sent to AI." : "The original audio will not be sent to AI."
            ), systemImage: "shield.checkered")
            Text(candidate.safeText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("取消") { model.cancelAudioImport(); dismiss() }
                Button("只加入安全内容") { model.confirmAudioImport(candidate); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }
}

/// 根视图：根据当前状态路由到 onboarding / empty / 主对话界面。
struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: SidecarTheme { model.appearanceMode.resolvedTheme(systemScheme: systemScheme) }

    var body: some View {
        ZStack {
            LuminousSurface()
                .ignoresSafeArea()
            if model.activeProfile == nil {
                OnboardingView(model: model)
            } else if model.session.noteContext == nil {
                EmptyNoteView(model: model)
            } else {
                ChatView(model: model)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .environment(\.sidecarTheme, scheme)
        .environment(\.locale, model.interfaceLocale)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .sheet(item: $model.pendingAppendPlan) { plan in
            WritebackPreviewView(model: model, initialPlan: plan)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(isPresented: $model.isHistoryPresented) {
            ConversationHistoryView(model: model)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(isPresented: $model.isCommandPalettePresented) {
            CommandPaletteView(model: model)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(item: $model.pendingImageImport) { candidate in
            ImagePrivacyPreviewView(model: model, candidate: candidate)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(item: $model.pendingAudioImport) { candidate in
            AudioPrivacyPreviewView(model: model, candidate: candidate)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .confirmationDialog(
            "清空当前对话？",
            isPresented: $model.isClearConversationConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空对话", role: .destructive) {
                Task { await model.clearCurrentConversation() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除这篇笔记在 Sidecar 中的问题、回答和运行记录，不会删除或修改 Notes 原文。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .notesSidecarOpenSettings)) { _ in
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct CommandPaletteView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidecarTheme) private var scheme
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
    }

    private var commands: [SlashCommand] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SlashCommand.all }
        return SlashCommand.all.filter {
            $0.displayName.localizedCaseInsensitiveContains(needle) ||
            $0.promptHint.localizedCaseInsensitiveContains(needle) ||
            $0.trigger.localizedCaseInsensitiveContains(needle)
        }
    }

    private var canRunCommand: Bool {
        guard session.noteContext != nil else { return false }
        if case .generating = session.state.phase { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("命令面板").font(.system(size: 17, weight: .semibold))
                    Text("选择后立即执行；不会写入输入框")
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                }
                Spacer()
                Text("⌘K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
            }

            TextField("搜索命令", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.Palette.separator(for: scheme)))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(commands) { command in
                        Button {
                            dismiss()
                            Task { await session.execute(command) }
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: command.iconName)
                                    .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(command.displayName))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(LocalizedStringKey(command.promptHint))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(command.trigger)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: 9))
                        .disabled(!canRunCommand)
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider().overlay(Tokens.Palette.separator(for: scheme))

            HStack(spacing: 8) {
                Button("刷新笔记") {
                    dismiss()
                    Task { await model.refreshContext() }
                }
                Button("历史") {
                    dismiss()
                    Task { @MainActor in model.isHistoryPresented = true }
                }
                .disabled(session.noteContext == nil)
                Button(model.isPinned ? "取消 Pin" : "Pin") { model.togglePinned() }
                Spacer()
                Button("设置…") {
                    dismiss()
                    model.openSettings()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(18)
        .frame(width: 470, height: 500)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }
}

extension Tokens.Palette {
    static func surfaceBackground(scheme: SidecarTheme) -> Color {
        Tokens.Palette.canvas(for: scheme)
    }
}

// MARK: - Empty

/// 空状态：Notes 未启动 / 未选笔记
struct EmptyNoteView: View {
    @ObservedObject var model: AppModel
    @State private var isReading = false
    @State private var showPasteSheet = false
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
            Text("打开 Notes 以开始")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
            Text("选中一篇笔记后，点击“读当前笔记”即可建对话。第一次会让 macOS 询问是否允许 Sidecar 控制 Notes。")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "notes://")!)
                    } label: {
                        Label("打开 Notes", systemImage: "arrow.up.right.square")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("o", modifiers: [.command])

                    Button {
                        Task { await readCurrentNote() }
                    } label: {
                        if isReading {
                            ProgressView().controlSize(.small)
                                .frame(minWidth: 120)
                        } else {
                            Label("读当前笔记", systemImage: "doc.text.magnifyingglass")
                                .frame(minWidth: 120)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isReading)
                }

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("自动化权限未授权？去系统设置", systemImage: "lock.shield")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)

                Button("Automation 不可用？使用粘贴模式") { showPasteSheet = true }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
            }
            Spacer()
            if let banner = model.statusBanner {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                    .padding(.bottom, 12)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPasteSheet) {
            ManualContextSheet { title, text in
                showPasteSheet = false
                Task { await model.usePastedContext(title: title, text: text) }
            }
            .environment(\.locale, model.interfaceLocale)
            .environment(\.sidecarTheme, scheme)
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
    }

    private func readCurrentNote() async {
        isReading = true
        defer { Task { @MainActor in isReading = false } }
        await model.refreshContext()
    }
}

// MARK: - Onboarding

/// 首次启动引导：分两段
/// 1) 选择一个模型服务商（preset 卡片网格 + 自定义入口）
/// 2) 打开 Notes + 授权 AppleScript 自动化
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var editing: ProviderProfile?
    @State private var apiKeyDraft: String = ""
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                step1_providers
                step2_notes
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editing) { p in
            ProviderEditor(
                profile: p,
                apiKey: $apiKeyDraft,
                onCancel: { editing = nil },
                onSave: { newProfile, key in
                    Task {
                        try? await model.upsertProfile(newProfile, apiKey: key)
                        editing = nil
                    }
                },
                onTest: { profile, key, done in
                    Task {
                        await ProviderTestRunner.runTest(profile: profile, key: key, into: { result in
                            Task { @MainActor in
                                await model.recordProviderTest(result, for: profile)
                                done(result)
                                model.statusBanner = result.statusLabel
                            }
                        })
                    }
                }
            )
            .frame(minWidth: 520, minHeight: 380)
            .environment(\.locale, model.interfaceLocale)
            .environment(\.sidecarTheme, scheme)
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Tokens.Palette.agentMint(for: scheme).opacity(0.18))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
            }
            Text("让 AI 靠近你的备忘录")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
            Text("密钥只保存在本机钥匙串。先选一个服务商，再连接 Apple Notes。")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var step1_providers: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepLabel(n: 1, title: "选择模型服务商")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                ForEach(ProviderPreset.allCases) { preset in
                    PresetCard(preset: preset) {
                        tapPreset(preset)
                    }
                }
            }
            HStack {
                Button {
                    tapCustom()
                } label: {
                    Label("自定义 OpenAI 兼容", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("点 preset · 填 API Key · 保存")
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
            }
        }
    }

    private var step2_notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepLabel(n: 2, title: "连接 Apple Notes")
            VStack(alignment: .leading, spacing: 12) {
                Text("打开 Notes 并选中一篇笔记，第一次会让 macOS 询问是否允许 Sidecar 控制 Notes。")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "notes://")!)
                    } label: {
                        Label("打开 Notes", systemImage: "note.text")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("自动化权限", systemImage: "lock.shield")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Tokens.Palette.controlFill(for: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Tokens.Palette.contextAmber(for: scheme).opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
    }

    private func stepLabel(n: Int, title: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Tokens.Palette.contextAmber(for: scheme).opacity(0.18))
                    .frame(width: 22, height: 22)
                Text("\(n)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
        }
    }

    // 点 preset：要 API Key 的开 sheet，本地的直接保存
    private func tapPreset(_ preset: ProviderPreset) {
        if preset.requiresAPIKey {
            editing = preset.makeProfile()
            apiKeyDraft = ""
        } else {
            // 本地 Ollama 直接入库
            let profile = preset.makeProfile()
            Task {
                try? await model.upsertProfile(profile, apiKey: nil)
            }
        }
    }

    private func tapCustom() {
        let profile = ProviderProfile(
            name: "自定义",
            kind: .openAICompatible,
            capabilities: [.streaming, .jsonMode],
            baseURL: "",
            defaultModel: ""
        )
        editing = profile
        apiKeyDraft = ""
    }
}

/// Preset 卡片
struct PresetCard: View {
    let preset: ProviderPreset
    let onTap: () -> Void
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(symbolBg.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(symbolBg)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(preset.displayName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Tokens.Palette.controlFill(for: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Tokens.Palette.separator(for: scheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var symbolBg: Color {
        switch preset {
        case .anthropic: return Tokens.Palette.capabilityViolet(for: scheme)
        case .openai:    return Tokens.Palette.agentMint(for: scheme)
        case .gemini:    return Tokens.Palette.capabilityViolet(for: scheme)
        case .deepseek:  return Tokens.Palette.contextAmber(for: scheme)
        case .moonshot, .kimiGlobal: return Tokens.Palette.contextAmber(for: scheme)
        case .zhipu:     return Tokens.Palette.capabilityViolet(for: scheme)
        case .minimax, .minimaxGlobal: return Tokens.Palette.agentMint(for: scheme)
        case .ollama:    return Tokens.Palette.statusSuccess(for: scheme)
        case .customOpenAI: return Tokens.Palette.tertiaryText(for: scheme)
        }
    }
}

// MARK: - Chat

/// 主聊天视图
struct ChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var state: ConversationState

    init(model: AppModel) {
        self.model = model
        self._state = ObservedObject(wrappedValue: model.session.state)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar(model: model)
                    .padding(.horizontal, 10)
                    .padding(.top, 9)
                    .padding(.bottom, 4)

                ContextStatusRow(model: model)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                ConversationView(model: model)

                ComposerView(model: model)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            LuminousMarginRail(phase: state.phase, hasContext: model.session.noteContext != nil)
                .allowsHitTesting(false)
        }
        .background(Color.clear)
    }
}

private struct ContextStatusRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @Environment(\.sidecarTheme) private var scheme
    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
    }
    var body: some View {
        if let note = session.noteContext {
            HStack(spacing: 7) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                Text(contextLabel(note))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(contextLabel(note))
        }
    }
    private func contextLabel(_ note: NoteContext) -> String {
        if case .generating = session.state.phase {
            return model.localizedFormat("已读取当前备忘录 · %lld 字", note.plaintext.count)
        }
        return model.localizedFormat("已读取「%@」· %lld 字", note.locator.titleSnapshot, note.plaintext.count)
    }
}

/// “流光边栏”的空间签名：颜色只沿面板外缘出现，不侵入正文阅读面。
private struct LuminousSurface: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        ZStack {
            Tokens.Palette.canvas(for: scheme)
            LinearGradient(
                colors: [
                    Tokens.Palette.accent(for: scheme).opacity(scheme.isDark ? 0.055 : 0.035),
                    .clear,
                    Tokens.Palette.accent(for: scheme).opacity(scheme.isDark ? 0.035 : 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                .stroke(
                    Tokens.Palette.accent(for: scheme).opacity(contrast == .increased ? 0.64 : 0.28),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .ignoresSafeArea()
    }
}

private struct LuminousMarginRail: View {
    let phase: ConversationState.Phase
    let hasContext: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidecarTheme) private var scheme
    @State private var travelling = false

    var body: some View {
        GeometryReader { geometry in
            let railHeight = max(220, geometry.size.height - 74)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Tokens.Palette.accent(for: scheme).opacity(hasContext ? 0.44 : 0.18))
                    .frame(width: 1, height: railHeight)

                if isGenerating {
                    Capsule()
                        .fill(Tokens.Palette.accentStrong(for: scheme))
                        .frame(width: 2, height: 72)
                        .blur(radius: 0.35)
                        .shadow(color: Tokens.Palette.accent(for: scheme).opacity(0.72), radius: 9)
                        .offset(y: reduceMotion ? railHeight * 0.42 : (travelling ? railHeight - 72 : 0))
                } else {
                    Circle()
                        .fill(idleColor)
                        .frame(width: 4, height: 4)
                        .shadow(color: idleColor.opacity(0.8), radius: 7)
                        .offset(y: railHeight * idlePosition)
                }
            }
            .frame(width: 12, height: railHeight)
            .position(x: geometry.size.width - 5, y: geometry.size.height / 2)
        }
        .onAppear { updateMotion() }
        .onChange(of: isGenerating) { _, _ in updateMotion() }
    }

    private var isGenerating: Bool {
        if case .generating = phase { return true }
        return false
    }

    private var idleColor: Color {
        switch phase {
        case .error: return Tokens.Palette.statusError(for: scheme)
        case .paused, .retrying: return Tokens.Palette.statusWarning(for: scheme)
        default: return Tokens.Palette.accent(for: scheme).opacity(hasContext ? 1 : 0.52)
        }
    }

    private var idlePosition: CGFloat {
        switch phase {
        case .error, .paused, .retrying: return 0.55
        default: return hasContext ? 0.20 : 0.82
        }
    }

    private func updateMotion() {
        travelling = false
        guard isGenerating, !reduceMotion else { return }
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
            travelling = true
        }
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, scheme: scheme, isEnabled: isEnabled)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let scheme: SidecarTheme
    let isEnabled: Bool
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? Tokens.Palette.accentForeground(for: scheme) : Tokens.Palette.disabledText(for: scheme))
            .frame(minWidth: 96, minHeight: 40)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(fill)
            )
            .onHover { hovered = $0 }
    }

    private var fill: Color {
        guard isEnabled else { return Tokens.Palette.disabledFill(for: scheme) }
        if configuration.isPressed { return Tokens.Palette.primaryPressed(for: scheme) }
        if hovered { return Tokens.Palette.primaryHover(for: scheme) }
        return Tokens.Palette.accent(for: scheme)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, scheme: scheme, isEnabled: isEnabled, compact: false)
    }
}

struct CompactSecondaryButtonStyle: ButtonStyle {
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, scheme: scheme, isEnabled: isEnabled, compact: true)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let scheme: SidecarTheme
    let isEnabled: Bool
    let compact: Bool
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: compact ? .medium : .bold))
            .foregroundStyle(isEnabled ? Tokens.Palette.accent(for: scheme) : Tokens.Palette.disabledText(for: scheme))
            .frame(minWidth: compact ? 72 : 96, minHeight: compact ? 32 : 40)
            .padding(.horizontal, compact ? 12 : 16)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 8 : 10)
                            .strokeBorder(isEnabled ? Tokens.Palette.controlBorder(for: scheme) : Color.clear, lineWidth: 1)
                    )
            )
            .onHover { hovered = $0 }
    }

    private var fill: Color {
        guard isEnabled else { return Tokens.Palette.disabledFill(for: scheme) }
        if configuration.isPressed { return Tokens.Palette.secondaryPressedFill(for: scheme) }
        if hovered { return Tokens.Palette.secondaryHoverFill(for: scheme) }
        return Tokens.Palette.controlFill(for: scheme)
    }
}
