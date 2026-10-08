import SwiftUI
import AppKit

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case providers, notes, general, privacy
        var id: String { rawValue }
        var title: String {
            switch self { case .providers: return "模型服务"; case .notes: return "Notes 连接"; case .general: return "窗口与通用"; case .privacy: return "隐私与数据" }
        }
        var icon: String {
            switch self { case .providers: return "sparkles"; case .notes: return "note.text"; case .general: return "switch.2"; case .privacy: return "lock.shield" }
        }
    }

    @ObservedObject var model: AppModel
    @State private var selection: Section = .providers
    @State private var editing: ProviderProfile?
    @State private var apiKeyDraft = ""
    @State private var showPresetSheet = false
    @State private var showPasteSheet = false
    @State private var showClearAllConfirmation = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: SidecarTheme { model.appearanceMode.resolvedTheme(systemScheme: systemScheme) }

    var body: some View {
        HSplitView {
            navigation.frame(minWidth: 172, idealWidth: 184, maxWidth: 200)
            detail.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            Tokens.Palette.canvas(for: scheme)
        }
        .background(alignment: .topLeading) {
            SettingsWindowChrome(
                scheme: scheme,
                title: model.interfaceText("Notes Sidecar 设置", "Notes Sidecar Settings")
            )
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .environment(\.sidecarTheme, scheme)
        .environment(\.locale, model.interfaceLocale)
        .sheet(isPresented: $showPresetSheet) {
            presetPicker
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(item: $editing) {
            profileEditor($0)
                .environment(\.locale, model.interfaceLocale)
                .environment(\.sidecarTheme, scheme)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .sheet(isPresented: $showPasteSheet) {
            ManualContextSheet { title, text in
                showPasteSheet = false
                Task { await model.usePastedContext(title: title, text: text) }
            }
            .environment(\.locale, model.interfaceLocale)
            .environment(\.sidecarTheme, scheme)
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .confirmationDialog("清空全部 Sidecar 对话？", isPresented: $showClearAllConfirmation, titleVisibility: .visible) {
            Button("清空全部对话", role: .destructive) { Task { await model.clearAllConversationData() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除 Sidecar 本地会话和草稿；不会修改 Notes，也不会删除钥匙串中的 API Key。")
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes Sidecar").font(.system(size: 17, weight: .semibold))
                Text("设置").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)

            ForEach(Section.allCases) { item in
                Button { selection = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(LocalizedStringKey(item.title))
                        Spacer()
                    }
                    .font(.system(size: 13, weight: selection == item ? .semibold : .regular))
                    .foregroundStyle(selection == item ? Tokens.Palette.primaryText(for: scheme) : Tokens.Palette.secondaryText(for: scheme))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(selection == item ? Tokens.Palette.selectedFill(for: scheme) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Tokens.Palette.accent(for: scheme), lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
            }
            Spacer()
            Label("所有请求从本机直连服务商", systemImage: "checkmark.shield")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.agentMint(for: scheme).opacity(0.78))
                .padding(16)
        }
        .background(reduceTransparency ? Tokens.Palette.raisedSurface(for: scheme) : Tokens.Palette.workspaceGlassSurface(for: scheme))
        .overlay(alignment: .trailing) { Rectangle().fill(Tokens.Palette.separator(for: scheme)).frame(width: 1) }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .providers: providersDetail
        case .notes: notesDetail
        case .general: generalDetail
        case .privacy: privacyDetail
        }
    }

    private var providersDetail: some View {
        settingsPage(title: "模型服务", subtitle: "密钥保存在本机钥匙串；内置服务商只需填写密钥。") {
            HStack {
                Text("服务商").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showPresetSheet = true } label: { Label("添加", systemImage: "plus") }
                    .buttonStyle(CompactSecondaryButtonStyle())
            }
            ForEach(model.profiles) { profile in
                ProviderSettingsRow(profile: profile, selected: profile.id == model.activeProfile?.id) {
                    Task { await model.setProfile(profile) }
                } edit: {
                    editing = profile; apiKeyDraft = ""
                } delete: {
                    Task { await model.deleteProfile(profile) }
                }
            }
            if model.profiles.isEmpty {
                SettingsEmpty(icon: "key", title: "还没有服务商", message: "添加 MiniMax、OpenAI、Anthropic 或自定义兼容服务。")
            }
        }
    }

    private var notesDetail: some View {
        settingsPage(title: "Notes 连接", subtitle: "Automation 用于读取当前笔记；Accessibility 只用于窗口跟随和未来的精确写回。") {
            SettingsGroup(title: "自动化", info: "Automation 权限后 AppleEvents 拉取当前选中笔记的正文。手动点「测试读取」会立刻跳一次真请求以验证。") {
                settingsRow("读取当前笔记", detail: "触发一次真实读取并显示结果") {
                    Button("测试读取") { Task { await model.refreshContext() } }
                }
                Divider()
                settingsRow("自动切换会话", detail: "在 Notes 选择其他笔记时同步切换") {
                    Toggle("", isOn: $model.autoSwitchNotes).labelsHidden().onChange(of: model.autoSwitchNotes) { _, _ in model.updatePreferences() }
                }
                if let banner = model.statusBanner {
                    Text(banner).font(.system(size: 11)).foregroundStyle(Tokens.Palette.statusWarning(for: scheme)).padding(.top, 4)
                }
            }

            SettingsGroup(title: "增强连接", info: "Accessibility 仅用于侧栏贴边于 Notes 窗口、读取窗口位置；不影响隐私防火墙或 API Key 读取。") {
                settingsRow("Accessibility", detail: model.isAccessibilityTrusted ? "已授权，可跟随 Notes 窗口" : "未授权；核心问答仍可使用") {
                    Button(model.isAccessibilityTrusted ? "已授权" : "请求权限") { model.requestAccessibilityPermission() }
                        .disabled(model.isAccessibilityTrusted)
                }
                Divider()
                settingsRow("跟随 Notes 窗口", detail: "Notes 移动或缩放时保持边栏贴边") {
                    Toggle("", isOn: $model.followNotesWindow).labelsHidden().onChange(of: model.followNotesWindow) { _, _ in model.updatePreferences() }
                }
                Divider()
                settingsRow("吸附方向", detail: "保留 14pt 桌面呼吸距离") {
                    Picker("", selection: $model.dockSide) { ForEach(AppModel.DockSide.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 90).onChange(of: model.dockSide) { _, _ in model.updatePreferences() }
                }
            }

            SettingsGroup(title: "兼容性探针", info: "只读取当前系统、Notes 版本和权限状态，不读取 Notes 私有数据库或附件二进制。可在每个目标 macOS 版本运行后对照结果。") {
                settingsRow("AppleScript、附件与 Accessibility", detail: model.compatibilityProbeReport?.summary ?? "检查当前 macOS / Notes 组合的可用能力") {
                    Button(model.isRunningCompatibilityProbe ? "检查中…" : "运行探针") {
                        Task { await model.runCompatibilityProbe() }
                    }
                    .disabled(model.isRunningCompatibilityProbe)
                }
                if let report = model.compatibilityProbeReport {
                    Text(report.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                }
            }

            SettingsGroup(title: "权限不可用时", info: "Automation / Accessibility 未授权时，仍可以以粘贴模式创建对话。本地会话与正常路径走同一份隐私检查。") {
                settingsRow("粘贴模式", detail: "不控制 Notes，建立一段只保存在 Sidecar 的对话") {
                    Button("粘贴内容…") { showPasteSheet = true }
                }
                Divider()
                settingsRow("系统设置", detail: "检查隐私与安全 → 自动化") {
                    Button("打开") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }
    }

    private var generalDetail: some View {
        settingsPage(title: "窗口与通用", subtitle: "让边栏保持稳定的空间位置，同时尊重系统外观与动效设置。") {
            SettingsGroup(title: "窗口", info: "吸附模式会在 Notes 移动后保持边栏贴边；独立模式不考虑 Notes 位置。") {
                settingsRow("窗口模式", detail: "吸附、独立或紧凑") {
                    Picker("", selection: $model.windowMode) { ForEach(AppModel.WindowMode.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 130).onChange(of: model.windowMode) { _, mode in SidecarPanelController.shared.setMode(mode); model.updatePreferences() }
                }
                Divider()
                settingsRow("关闭按钮", detail: "菜单栏模式建议隐藏") {
                    Picker("", selection: $model.closeBehavior) { ForEach(AppModel.CloseBehavior.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 130).onChange(of: model.closeBehavior) { _, _ in model.updatePreferences() }
                }
                Divider()
                settingsRow("窗口置顶", detail: model.isPinned ? "始终显示在其他应用上方" : "像普通窗口一样可被其他应用遮挡") {
                    Toggle("", isOn: Binding(
                        get: { model.isPinned },
                        set: { _ in model.togglePinned() }
                    )).labelsHidden()
                }
                Divider()
                settingsRow("开机启动", detail: "登录 Mac 后自动启动 Notes Sidecar") {
                    Toggle("", isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                }
            }
            SettingsGroup(title: "外观", info: "正文颜色与玻璃透明度以系统动效设置为优先；Liquid Glass 在「减少透明度」下会退回不透明表面。") {
                settingsRow("语言", detail: "简体中文系统使用中文，其他系统默认英文") {
                    Picker("", selection: $model.interfaceLanguage) {
                        ForEach(AppModel.InterfaceLanguage.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .onChange(of: model.interfaceLanguage) { _, _ in
                        model.statusBanner = nil
                        model.updatePreferences()
                    }
                }
                Divider()
                settingsRow("配色", detail: "正文保持高对比度") {
                    Picker("", selection: $model.appearanceMode) { ForEach(AppModel.AppearanceMode.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 130).onChange(of: model.appearanceMode) { _, _ in model.updatePreferences() }
                }
                Divider()
                settingsRow("默认写回", detail: "追加仍会检查笔记版本并显示预览") {
                    Picker("", selection: $model.defaultWritebackMode) { ForEach(AppModel.DefaultWritebackMode.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 130).onChange(of: model.defaultWritebackMode) { _, _ in model.updatePreferences() }
                }
            }
            SettingsGroup(title: "快捷键", info: "⌥⌘N 是 Carbon 热运行，无论窗口与状态都会生效。⌥⌘R 与 ⇧⌘W 需要窗口处于按键状态。") {
                settingsRow("显示 / 隐藏边栏", detail: "全局快捷键") { Text("⌥⌘N").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
                Divider()
                settingsRow("刷新当前笔记", detail: "应用内快捷键") { Text("⌥⌘R").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
                Divider()
                settingsRow("执行默认写回", detail: model.defaultWritebackMode.label) { Text("⇧⌘W").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
            }
        }
    }

    private var privacyDetail: some View {
        settingsPage(title: "隐私与数据", subtitle: "笔记正文只在发起请求时直达所选服务商；开发者不提供中转服务器。") {
            SettingsGroup(title: "隐私防火墙", info: "扫描检测出常见 API Key / Token / App Secret / JWT / 私钥和个人信息后，敏感行不会提交给服务商，安全行仍可作为上下文。扫描出错则一律阻止请求。") {
                Label("始终开启", systemImage: "checkmark.shield.fill").foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                Text("检测常见密钥、密码和令牌；扫描失败时阻止远程请求。API Key 不写入历史或日志。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsGroup(title: "历史", info: "只限本机对话历史；API Key、设置文件、Note 原文都未触及。") {
                settingsRow("保留期限", detail: "仅影响 Sidecar 本地会话") {
                    Picker("", selection: $model.historyRetention) { ForEach(AppModel.HistoryRetention.allCases) { Text(LocalizedStringKey($0.label)).tag($0) } }
                        .labelsHidden().frame(width: 120).onChange(of: model.historyRetention) { _, _ in model.updatePreferences() }
                }
                Divider()
                HStack {
                    Button("导出全部对话…") { model.exportAllConversations() }
                    Spacer()
                    Button("清空全部对话…", role: .destructive) { showClearAllConfirmation = true }
                }
            }
            SettingsGroup(title: "本地存储", info: "对话以原子 JSON 文件保存在 Application Support；API Key 单独保存在 macOS 钥匙串。沙箱后需要 app group 才能在 App 与主之间交叉读。") {
                Text("对话目前以原子 JSON 文件保存在 Application Support；API Key 单独保存在 macOS 钥匙串。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsPage<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: Tokens.Font.pageTitle, weight: .bold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(24).frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func settingsRow<Trailing: View>(_ title: String, detail: String, @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        SettingsRowView(title: title, detail: detail, trailing: trailing)
    }

    private var presetPicker: some View {
        PresetPickerSheet { preset in
            showPresetSheet = false; editing = preset.makeProfile(); apiKeyDraft = ""
        } onCustom: {
            showPresetSheet = false
            editing = ProviderProfile(name: "自定义", kind: .openAICompatible, capabilities: [.streaming, .jsonMode])
            apiKeyDraft = ""
        }
    }

    private func profileEditor(_ profile: ProviderProfile) -> some View {
        ProviderEditor(profile: profile, apiKey: $apiKeyDraft, onCancel: { editing = nil }, onSave: { updated, key in
            Task { try? await model.upsertProfile(updated, apiKey: key); editing = nil }
        }, onTest: { tested, key, done in
            Task {
                await ProviderTestRunner.runTest(profile: tested, key: key) { result in
                    Task { @MainActor in await model.recordProviderTest(result, for: tested); done(result) }
                }
            }
        })
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var info: String? = nil
    @ViewBuilder let content: () -> Content
    @State private var infoHovered = false
    @State private var infoPresented = false
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: Tokens.Font.sectionTitle, weight: .bold))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                if let info {
                    Button {
                        infoPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.Palette.secondaryText(for: scheme).opacity(infoHovered ? 1 : 0.62))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .help(localizedInfo(info))
                        .onHover { infoHovered = $0 }
                        .popover(isPresented: $infoPresented, arrowEdge: .bottom) {
                            Text(localizedInfo(info))
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 300, alignment: .leading)
                                .padding(14)
                                .background(Tokens.Palette.raisedSurface(for: scheme))
                        }
                        .accessibilityLabel(Text(LocalizedStringKey("查看说明")))
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(16)
        .background(Tokens.Palette.contentSurface(for: scheme), in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous).stroke(Tokens.Palette.separator(for: scheme)))
    }

    private func localizedInfo(_ key: String) -> String {
        guard locale.identifier.lowercased().hasPrefix("en"),
              let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

private struct SettingsRowView<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovered = false
    @Environment(\.sidecarTheme) private var scheme
    init(title: String, detail: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.system(size: Tokens.Font.label, weight: .medium))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                Text(LocalizedStringKey(detail)).font(.system(size: Tokens.Font.meta))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovered ? Tokens.Palette.hoverFill(for: scheme) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct ProviderSettingsRow: View {
    let profile: ProviderProfile; let selected: Bool
    let select: () -> Void; let edit: () -> Void; let delete: () -> Void
    @State private var confirmDelete = false
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.locale) private var locale
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(LocalizedStringKey(profile.name)).font(.system(size: 13, weight: .semibold)); if selected { Text("默认").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tokens.Palette.agentMint(for: scheme)) } }
                Text("\(profile.defaultModel) · \(localizedStatus)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(selected ? "已启用" : "启用", action: select)
                .buttonStyle(CompactSecondaryButtonStyle())
                .disabled(selected)
            Button("编辑", action: edit)
                .buttonStyle(CompactSecondaryButtonStyle())
            Menu { Button("删除服务商…", role: .destructive) { confirmDelete = true } } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(13)
        .background(selected ? Tokens.Palette.selectedFill(for: scheme) : Tokens.Palette.raisedSurface(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Tokens.Palette.accent(for: scheme) : Tokens.Palette.separator(for: scheme), lineWidth: 1))
        .confirmationDialog("删除“\(profile.name)”？", isPresented: $confirmDelete) {
            Button("删除服务商和钥匙串密钥", role: .destructive, action: delete); Button("取消", role: .cancel) {}
        }
    }
    private var statusColor: Color {
        switch profile.lastTestStatus { case .connected: return Tokens.Palette.statusSuccess(for: scheme); case .authFailed, .networkFailed: return Tokens.Palette.statusError(for: scheme); case .rateLimited, .unsupported: return Tokens.Palette.statusWarning(for: scheme); case .unknown: return .secondary }
    }

    private var localizedStatus: String {
        let usesChinese = locale.identifier.lowercased().hasPrefix("zh-hans")
            || locale.identifier.lowercased().hasPrefix("zh_cn")
            || locale.identifier.lowercased().hasPrefix("zh-cn")
        switch profile.lastTestStatus {
        case .unknown:
            return usesChinese ? "未测试" : "Not tested"
        case .connected(let date):
            return "\(usesChinese ? "已连接" : "Connected") · \(ProviderTestStatus.short(date))"
        case .authFailed(let detail):
            return "\(usesChinese ? "认证失败" : "Authentication failed") · \(detail)"
        case .networkFailed(let detail):
            return "\(usesChinese ? "网络失败" : "Network failed") · \(detail)"
        case .rateLimited(let date):
            return "\(usesChinese ? "限流" : "Rate limited") · \(ProviderTestStatus.short(date))"
        case .unsupported(let detail):
            return "\(usesChinese ? "不支持" : "Unsupported") · \(detail)"
        }
    }
}

private struct SettingsEmpty: View {
    let icon: String; let title: String; let message: String
    var body: some View { VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 22)); Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .semibold)); Text(LocalizedStringKey(message)).font(.system(size: 11)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(28) }
}

struct ManualContextSheet: View {
    let submit: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = "粘贴的内容"
    @State private var text = ""
    @Environment(\.sidecarTheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用粘贴模式").font(.system(size: 17, weight: .semibold))
            Text("适用于 Automation 不可用时。内容只进入 Sidecar 本地会话，发送时仍经过隐私检查。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("标题", text: $title).liquidField()
            TextEditor(text: $text).font(.system(size: 12)).frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: Tokens.Radius.input))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.input).stroke(Tokens.Palette.controlBorder(for: scheme), lineWidth: 1))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("开始对话") { submit(title, text) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 390)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
    }
}

public struct PresetPickerSheet: View {
    let onPick: (ProviderPreset) -> Void
    let onCustom: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidecarTheme) private var scheme
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加服务商")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                    Text("选择要连接的模型服务商")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Tokens.Palette.controlFill(for: scheme), in: Circle())
                        .overlay(Circle().stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ProviderPreset.allCases.filter { $0 != .customOpenAI }) { preset in
                        PresetCard(preset: preset) { onPick(preset) }
                    }
                }
                .padding(.vertical, 1)
            }
            Button { onCustom() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .frame(width: 28, height: 28)
                    Text("自定义 OpenAI 兼容")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(width: 560, height: 500)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
    }
}

private struct SettingsWindowChrome: NSViewRepresentable {
    let scheme: SidecarTheme
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Settings scenes otherwise derive a localized system title from
            // macOS's language (for example, `NotesSidecar设置`), which can
            // disagree with the language selected inside the app.
            window.title = title
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line
            switch scheme {
            case .light:
                window.backgroundColor = NSColor(calibratedRed: 237/255, green: 243/255, blue: 246/255, alpha: 1)
            case .dark:
                window.backgroundColor = NSColor(calibratedWhite: 26/255, alpha: 1)
            case .technology:
                window.backgroundColor = NSColor(calibratedRed: 13/255, green: 24/255, blue: 33/255, alpha: 1)
            }
        }
    }
}
