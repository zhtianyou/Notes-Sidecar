import SwiftUI

/// 底部输入：问题、快捷动作、发送/停止与模型状态共用一个稳定控制面。
struct ComposerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @ObservedObject private var state: ConversationState
    @FocusState private var focused: Bool
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
        self._state = ObservedObject(wrappedValue: model.session.state)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !commandSuggestions.isEmpty {
                CommandSuggestions(commands: commandSuggestions) { command in
                    session.draft = ""
                    focused = false
                    Task { await session.execute(command) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }

            VStack(alignment: .leading, spacing: 0) {
                if let notice = session.privacyNotice {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                        Text(notice)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Tokens.Palette.statusFill(for: .warning, scheme: scheme))
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .accessibilityElement(children: .combine)
                }
                if state.turns.last(where: { $0.role == .user }) != nil, case .paused = state.phase {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                        Text("上次回复被中断")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                        Spacer()
                        Button {
                            Task { await session.retryLastQuestion() }
                        } label: {
                            Label("继续生成", systemImage: "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("重新发出上次的问题，继续这一轮对话")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Tokens.Palette.statusFill(for: .warning, scheme: scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Tokens.Palette.statusWarning(for: scheme).opacity(0.34), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .accessibilityElement(children: .combine)
                } else if let errMsg = currentErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Tokens.Palette.statusError(for: scheme))
                        Text(errMsg)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.statusError(for: scheme))
                            .lineLimit(2)
                        Spacer()
                        Button {
                            Task { await session.retryLastQuestion() }
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Tokens.Palette.statusFill(for: .error, scheme: scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Tokens.Palette.statusError(for: scheme).opacity(0.34), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                if let command = matchedCommand {
                    HStack(spacing: 6) {
                        Image(systemName: command.iconName)
                        Text("\(command.displayName) · 整篇笔记")
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            session.draft = session.draft.replacingOccurrences(of: command.trigger, with: "")
                                .trimmingCharacters(in: .whitespaces)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除快捷动作")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                }

                if let image = session.imageContextAttachment {
                    HStack(spacing: 7) {
                        Image(systemName: "photo.badge.checkmark")
                            .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                        Text("图片上下文 · \(image.fileName)")
                            .lineLimit(1)
                        if image.containsPrivateContent {
                            Text("已排除 \(image.excludedLineCount) 行隐私内容")
                                .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                        } else {
                            Text("原图不上传")
                                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                        }
                        Spacer(minLength: 4)
                        Button {
                            session.removeImageContext()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除图片上下文")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                    .padding(.horizontal, 13)
                    .padding(.top, 9)
                }
                if let audio = session.audioContextAttachment {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.badge.checkmark")
                            .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                        Text("音频转写 · \(audio.fileName)").lineLimit(1)
                        Text(audio.containsPrivateContent ? "已排除 \(audio.excludedSegmentCount) 个隐私片段" : "原始音频不上传")
                            .foregroundStyle(audio.containsPrivateContent ? Tokens.Palette.statusWarning(for: scheme) : Tokens.Palette.secondaryText(for: scheme))
                        Spacer(minLength: 4)
                        Button { session.removeAudioContext() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("移除音频上下文")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                    .padding(.horizontal, 13).padding(.top, 9)
                }

                HStack(alignment: .bottom, spacing: 9) {
                    HStack(alignment: .bottom, spacing: 9) {
                        Menu {
                            Button {
                                Task { await model.chooseImageForLocalRecognition() }
                            } label: {
                                Label("本机识别图片…", systemImage: "photo.badge.magnifyingglass")
                            }
                            .disabled(model.isAnalyzingImage)
                            Button {
                                Task { await model.chooseAudioForLocalTranscription() }
                            } label: {
                                Label("本地转写音频…", systemImage: "waveform")
                            }
                            .disabled(model.isTranscribingAudio)
                            Divider()
                            ForEach(SlashCommand.all) { command in
                                Button {
                                    session.draft = ""
                                    focused = false
                                    Task { await session.execute(command) }
                                } label: {
                                    Label {
                                        Text(LocalizedStringKey(command.displayName))
                                    } icon: {
                                        Image(systemName: command.iconName)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Tokens.Palette.controlFill(for: scheme), in: Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("插入快捷动作")
                        .accessibilityLabel("添加图片或快捷动作")

                        TextField("继续问这篇备忘录…", text: $session.draft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                            .lineLimit(1...8)
                            .focused($focused)
                            .onSubmit {
                                guard canSend else { return }
                                Task { await model.sendFromMenu() }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.input, style: .continuous)
                            .fill(Tokens.Palette.controlFill(for: scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.input, style: .continuous)
                                    .stroke(
                                        focused
                                            ? Tokens.Palette.accent(for: scheme)
                                            : Tokens.Palette.controlBorder(for: scheme),
                                        lineWidth: focused ? 2 : 1
                                    )
                            )
                    )

                    Button(action: sendOrStop) {
                        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Tokens.Palette.accentForeground(for: scheme))
                            .frame(width: 40, height: 40)
                            .background(sendColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !isGenerating)
                    .opacity((canSend || isGenerating) ? 1 : 0.38)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityLabel(isGenerating ? "停止生成" : "发送")
                    .help(isGenerating ? "停止生成 (⌘.)" : "发送 (⌘↩)")
                }

                HStack(spacing: 6) {
                if let profile = model.activeProfile {
                    Picker(providerTitle, selection: Binding(
                        get: { model.activeProfile?.id ?? "" },
                        set: { providerID in
                            guard let selected = model.profiles.first(where: { $0.id == providerID }) else { return }
                            Task { await model.setProfile(selected) }
                        }
                    )) {
                        ForEach(model.profiles) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .frame(maxWidth: 138)
                    .accessibilityLabel(providerTitle)

                    Picker("模型", selection: Binding(
                        get: {
                            model.isRefreshingModelCatalog(for: profile.id) ? "" : profile.defaultModel
                        },
                        set: { model.setDefaultModel($0) }
                    )) {
                        if allModels(for: profile).isEmpty {
                            Text(model.isRefreshingModelCatalog(for: profile.id) ? loadingModelsTitle : noModelsTitle).tag("")
                        } else {
                            ForEach(allModels(for: profile), id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                        }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .frame(maxWidth: 154)
                    .accessibilityLabel(modelTitle)

                    Button {
                        Task { await model.fetchAvailableModels() }
                    } label: {
                        if model.isFetchingModels || model.isRefreshingModelCatalog(for: profile.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help(usesChinese ? "刷新模型列表" : "Refresh model list")
                    .disabled(model.isFetchingModels || model.isRefreshingModelCatalog(for: profile.id))

                    Picker(reasoningTitle, selection: Binding(
                        get: { profile.reasoningEffort },
                        set: { model.setReasoningEffort($0) }
                    )) {
                        if reasoningEfforts(for: profile).isEmpty {
                            Text(reasoningUnavailableTitle).tag(profile.reasoningEffort)
                        } else {
                            ForEach(reasoningEfforts(for: profile)) { effort in
                                Text(reasoningLabel(for: effort)).tag(effort)
                            }
                        }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .frame(maxWidth: 112)
                    .disabled(reasoningEfforts(for: profile).isEmpty)
                    .accessibilityLabel(reasoningTitle)
                    .help(reasoningHelp(for: profile.reasoningEffort))
                }
                Spacer(minLength: 0)
                Text(isGenerating ? "⌘. 停止" : "⌘↩ 发送")
                    .font(.system(size: 9))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                }
                .font(.system(size: 10))
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 9)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: commandSuggestions.count)
    }

    private var matchedCommand: SlashCommand? {
        SlashCommand.match(session.draft)
    }

    private var commandSuggestions: [SlashCommand] {
        let draft = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.hasPrefix("/"), !draft.contains(" "), !isGenerating else { return [] }
        return SlashCommand.all.filter { draft == "/" || $0.trigger.hasPrefix(draft) }
    }

    private var isGenerating: Bool {
        if case .generating = state.phase { return true }
        return false
    }

    private var currentErrorMessage: String? {
        state.currentErrorMessage
    }

    private var reasoningEffortHint: String {
        guard let effort = model.activeProfile?.reasoningEffort else { return usesChinese ? "默认" : "Default" }
        switch effort {
        case .low:    return usesChinese ? "快速、费用低、质量一般" : "Fast, lower cost, standard quality"
        case .medium: return usesChinese ? "平衡默认" : "Balanced default"
        case .high:   return usesChinese ? "推理深入、响应时间显著加长" : "Deeper reasoning, significantly slower"
        case .xhigh:  return usesChinese ? "上限推理、响应极长" : "Maximum reasoning, very slow"
        case .max:    return usesChinese ? "不设上限，仅限支持的模型" : "No fixed limit; supported models only"
        }
    }

    private var usesChinese: Bool {
        locale.identifier.lowercased().hasPrefix("zh-hans")
    }

    private var providerTitle: String { usesChinese ? "服务商" : "Provider" }
    private var modelTitle: String { usesChinese ? "模型" : "Model" }
    private var reasoningTitle: String { usesChinese ? "思考强度" : "Reasoning" }
    private var noModelsTitle: String { usesChinese ? "暂无模型，请刷新" : "No models — refresh" }
    private var loadingModelsTitle: String { usesChinese ? "正在刷新模型…" : "Refreshing models…" }
    private var reasoningUnavailableTitle: String { usesChinese ? "不支持推理" : "Not supported" }

    private func reasoningLabel(for effort: ReasoningEffort) -> String {
        if usesChinese { return effort.label }
        switch effort {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Very High"
        case .max: return "Maximum"
        }
    }

    private func reasoningHelp(for effort: ReasoningEffort) -> String {
        let prefix = usesChinese ? "仅在所选模型支持推理时可用。" : "Available only when the selected model supports reasoning."
        return "\(prefix) \(reasoningLabel(for: effort)) → \(reasoningEffortHint)"
    }

    private var canSend: Bool {
        guard let profile = model.activeProfile else { return false }
        return !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isGenerating &&
            !profile.defaultModel.isEmpty &&
            !model.isRefreshingModelCatalog(for: profile.id)
    }

    private var sendColor: Color {
        isGenerating ? Tokens.Palette.statusError(for: scheme) : Tokens.Palette.accent(for: scheme)
    }

    private func allModels(for profile: ProviderProfile) -> [String] {
        guard !model.isRefreshingModelCatalog(for: profile.id) else { return [] }
        var seen = Set<String>()
        var models = profile.availableModels.filter { seen.insert($0).inserted }
        if !profile.defaultModel.isEmpty, seen.insert(profile.defaultModel).inserted {
            models.append(profile.defaultModel)
        }
        return models
    }

    private func reasoningEfforts(for profile: ProviderProfile) -> [ReasoningEffort] {
        profile.supportedReasoningEfforts(for: profile.defaultModel)
    }

    private func sendOrStop() {
        if isGenerating {
            model.stopFromMenu()
        } else if canSend {
            Task { await model.sendFromMenu() }
        }
    }
}

private struct CommandSuggestions: View {
    let commands: [SlashCommand]
    let select: (SlashCommand) -> Void
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(commands) { command in
                Button {
                    select(command)
                } label: {
                    HStack(spacing: 9) {
                        Text(command.trigger)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Tokens.Palette.capabilityViolet(for: scheme))
                            .frame(width: 78, alignment: .leading)
                        Text(LocalizedStringKey(command.displayName))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                        Spacer()
                        Text(LocalizedStringKey(command.promptHint))
                            .font(.system(size: 9))
                            .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Tokens.Palette.insetSurface(for: scheme).opacity(0.98))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.Palette.capabilityViolet(for: scheme).opacity(0.26), lineWidth: 1))
        )
    }
}
