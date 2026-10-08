import SwiftUI

/// 添加/编辑服务商表单
public struct ProviderEditor: View {
    @State var profile: ProviderProfile
    @Binding var apiKey: String
    let onCancel: () -> Void
    let onSave: (ProviderProfile, String) -> Void
    let onTest: ((ProviderProfile, String, @escaping @MainActor (ProviderTestRunner.Result) -> Void) -> Void)?

    @State private var testStatus: String? = nil
    @State private var testRunning = false
    @State private var modelRefreshRunning = false
    @State private var modelList: [String] = []
    @State private var newModelInput: String = ""
    @State private var customHeadersText: String
    @State private var advancedExpanded = false
    @State private var oauthConnected = false
    @State private var oauthRunning = false
    @State private var oauthStatus: String?
    @Environment(\.sidecarTheme) private var scheme
    private let labelWidth: CGFloat = 108

    public init(
        profile: ProviderProfile,
        apiKey: Binding<String>,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ProviderProfile, String) -> Void,
        onTest: ((ProviderProfile, String, @escaping @MainActor (ProviderTestRunner.Result) -> Void) -> Void)? = nil
    ) {
        self._profile = State(initialValue: profile)
        self._apiKey = apiKey
        self.onCancel = onCancel
        self.onSave = onSave
        self.onTest = onTest
        self._customHeadersText = State(initialValue: profile.customHeaders.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if builtInPreset == nil {
                    Text("添加自定义服务商")
                        .font(.system(size: Tokens.Font.sectionTitle, weight: .bold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                } else {
                    (Text("配置") + Text(" ") + Text(LocalizedStringKey(profile.name)))
                        .font(.system(size: Tokens.Font.sectionTitle, weight: .bold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                }
                Spacer()
                Button(action: onCancel) {
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

            if let preset = builtInPreset {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                    VStack(alignment: .leading, spacing: 2) {
                    (Text("官方内置服务商") + Text(" · ") + Text(LocalizedStringKey(preset.displayName)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                        Text("地址、协议、鉴权方式和模型目录由 Sidecar 自动维护")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                        if let regionDetail = providerRegionDetail {
                            Text(regionDetail)
                                .font(.system(size: 10))
                                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.Palette.agentMint(for: scheme).opacity(0.10)))
            } else {
                HStack(spacing: 12) {
                    Text("名称").frame(width: labelWidth, alignment: .leading)
                    TextField("显示名", text: $profile.name).liquidField()
                    Picker("类型", selection: $profile.kind) {
                        ForEach([ProviderKind.openAICompatible, .anthropic, .ollama], id: \.self) { k in
                            Text(LocalizedStringKey(k.displayName)).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .onChange(of: profile.kind) { _, new in
                        if profile.baseURL.isEmpty { profile.baseURL = new.defaultBaseURL }
                        if profile.defaultModel.isEmpty { profile.defaultModel = new.defaultModel }
                    }
                }

                HStack(spacing: 12) {
                    Text("Base URL").frame(width: labelWidth, alignment: .leading)
                    TextField(profile.kind.defaultBaseURL, text: $profile.baseURL).liquidField()
                }
            }
            if builtInPreset == .ollama {
                HStack(spacing: 12) {
                    Text("服务地址").frame(width: labelWidth, alignment: .leading)
                    TextField("http://127.0.0.1:11434/v1", text: $profile.baseURL)
                        .liquidField()
                }
            }
            if builtInPreset == .openai {
                HStack(spacing: 12) {
                    Text("授权方式").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: $profile.authenticationMode) {
                        ForEach(ProviderAuthenticationMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if profile.kind.requiresAPIKey && (profile.authenticationMode == .apiKey || builtInPreset != .openai) {
                HStack(spacing: 12) {
                    Text("API Key").frame(width: labelWidth, alignment: .leading)
                    SecureField(builtInPreset == nil ? "可选，保存到钥匙串" : "粘贴密钥；留空则保留已保存密钥", text: $apiKey)
                        .liquidField()
                }
            } else if builtInPreset == .openai {
                HStack(spacing: 10) {
                    Image(systemName: oauthConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                        .foregroundStyle(oauthConnected ? Tokens.Palette.statusSuccess(for: scheme) : Tokens.Palette.agentMint(for: scheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(oauthConnected ? "已连接 ChatGPT" : "尚未连接 ChatGPT")
                            .font(.system(size: 12, weight: .semibold))
                        Text(oauthStatus ?? SidecarLocalizer.text("浏览器登录；访问令牌与刷新令牌只保存在本机钥匙串。", "Sign in in your browser. Access and refresh tokens stay only in the local Keychain."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if oauthConnected {
                        Button("断开") { Task { await disconnectChatGPT() } }
                    }
                    Button(oauthConnected ? "重新登录" : "使用 ChatGPT 登录") {
                        Task { await connectChatGPT() }
                    }
                    .disabled(oauthRunning)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.Palette.agentMint(for: scheme).opacity(0.08)))
            }

            // 模型目录只能来自授权后的 Provider 实际响应，绝不预填过期型号。
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("模型").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: $profile.defaultModel) {
                        if allModels.isEmpty {
                            Text(SidecarLocalizer.text("尚未加载模型", "No models loaded")).tag("")
                        } else {
                            ForEach(allModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        if !profile.defaultModel.isEmpty && !allModels.contains(profile.defaultModel) {
                            Text(profile.defaultModel + SidecarLocalizer.text(" · 当前", " · Current"))
                                .tag(profile.defaultModel)
                        }
                    }
                    .labelsHidden()
                    Button(action: refreshModels) {
                        if modelRefreshRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(SidecarLocalizer.text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(modelRefreshRunning || testRunning)
                }
                HStack(spacing: 12) {
                    Color.clear.frame(width: labelWidth, height: 1)
                    TextField("或手填新模型名", text: $newModelInput)
                        .liquidField()
                        .onSubmit { addNewModel() }
                    Button("添加") { addNewModel() }
                        .disabled(newModelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if allModels.isEmpty {
                    Text(SidecarLocalizer.text("完成授权后点击“刷新”以获取当前可用模型；若服务商不提供模型目录，也可手动输入模型 ID。", "After authorization, click Refresh to load the models currently available to your account. If the provider does not expose a model catalog, enter a model ID manually."))
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                        .padding(.leading, labelWidth + 12)
                }
            }

            // 思考强度（仅对支持 .reasoning 的服务商）
            if profile.capabilities.contains(.reasoning) {
                HStack(spacing: 12) {
                    Text("思考强度").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: $profile.reasoningEffort) {
                        ForEach(ReasoningEffort.allCases) { r in
                            Text(LocalizedStringKey(r.label)).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            DisclosureGroup("高级请求设置", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("超时").frame(width: 88, alignment: .leading)
                        TextField("60", value: $profile.requestTimeout, format: .number)
                            .liquidField(horizontal: 9, vertical: 5)
                            .frame(width: 90)
                        Text("秒").foregroundStyle(.secondary)
                        Spacer()
                        Text("最大输出").foregroundStyle(.secondary)
                        TextField("4096", value: $profile.maxOutputTokens, format: .number)
                            .liquidField(horizontal: 9, vertical: 5)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("温度").frame(width: 88, alignment: .leading)
                        Slider(value: $profile.temperature, in: 0...2, step: 0.1)
                        Text(profile.temperature, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit().frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("自定义请求头（每行 Name: Value）")
                            .font(.system(size: 11, weight: .medium))
                        TextEditor(text: $customHeadersText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 64)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Tokens.Palette.controlFill(for: scheme), in: RoundedRectangle(cornerRadius: Tokens.Radius.input))
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.input).stroke(Tokens.Palette.controlBorder(for: scheme), lineWidth: 1))
                        Text("Authorization、Cookie、x-api-key 不允许写在这里；密钥仍只进入钥匙串。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }

            // 测试反馈条（留在 sheet 内）
            if testRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("测试中…").font(.system(size: 12))
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Palette.controlFill(for: scheme)))
            } else if let s = testStatus {
                Text(s)
                    .font(.system(size: 12))
                    .foregroundStyle(testColor(s))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(testColor(s).opacity(0.10)))
            }

            HStack(spacing: 8) {
                Button {
                    testRunning = true
                    testStatus = nil
                    if let cb = onTest {
                        cb(profileForSave(), apiKey) { result in
                            self.testStatus = result.statusLabel
                            if !result.models.isEmpty {
                                var seen = Set<String>()
                                self.modelList = result.models.filter { seen.insert($0).inserted }
                                if !self.modelList.contains(self.profile.defaultModel) {
                                    self.profile.defaultModel = self.modelList.first ?? ""
                                }
                            }
                            self.testRunning = false
                        }
                    } else {
                        Task { await runDirectTest() }
                    }
                } label: {
                    if testRunning {
                        HStack { ProgressView().controlSize(.small); Text("测试连接") }
                    } else {
                        Text("测试连接")
                    }
                }
                .disabled(testRunning)
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                Button(builtInPreset == nil ? "保存" : "保存并启用") { onSave(profileForSave(), apiKey) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 620)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
        .onAppear {
            // 把 preset 推荐的模型填进列表（如果还没有）
            modelList = profile.availableModels
            if builtInPreset == .openai {
                Task { @MainActor in
                    let connected = await OpenAIChatGPTAuth.shared.isConnected(profile: profile)
                    oauthConnected = connected
                    if connected, profile.authenticationMode == .chatGPTSubscription {
                        refreshModels()
                    }
                }
            }
        }
        .onChange(of: modelList) { _, new in
            profile.availableModels = new
        }
    }

    @MainActor
    private func connectChatGPT() async {
        oauthRunning = true
        oauthStatus = SidecarLocalizer.text("等待浏览器授权…", "Waiting for browser authorization…")
        defer { oauthRunning = false }
        do {
            try await OpenAIChatGPTAuth.shared.signIn(profile: profile)
            oauthConnected = true
            oauthStatus = SidecarLocalizer.text("授权成功，可使用符合条件的 ChatGPT 订阅额度", "Authorized. Eligible ChatGPT subscription quota is available.")
            refreshModels()
        } catch {
            oauthStatus = SidecarLocalizer.text(
                "授权失败：\(error.localizedDescription)",
                "Authorization failed. Check your network connection and try again."
            )
        }
    }

    @MainActor
    private func disconnectChatGPT() async {
        try? await OpenAIChatGPTAuth.shared.disconnect(profile: profile)
        oauthConnected = false
        oauthStatus = SidecarLocalizer.text("已断开", "Disconnected")
    }

    private var allModels: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in modelList where seen.insert(m).inserted {
            out.append(m)
        }
        if !profile.defaultModel.isEmpty, seen.insert(profile.defaultModel).inserted {
            out.append(profile.defaultModel)
        }
        return out
    }

    private var builtInPreset: ProviderPreset? {
        guard let raw = profile.preset else { return nil }
        return ProviderPreset(rawValue: raw)
    }

    /// Kimi has separate China and global developer platforms. Show the exact
    /// Key origin next to the fixed endpoint so a key cannot be accidentally
    /// saved into the wrong preset.
    private var providerRegionDetail: String? {
        switch builtInPreset {
        case .moonshot:
            return SidecarLocalizer.text(
                "中国区：仅使用 platform.kimi.com 创建的 API Key · api.moonshot.cn",
                "China: use only an API Key created at platform.kimi.com · api.moonshot.cn"
            )
        case .kimiGlobal:
            return SidecarLocalizer.text(
                "国际区：仅使用 platform.kimi.ai 创建的 API Key · api.moonshot.ai",
                "Global: use only an API Key created at platform.kimi.ai · api.moonshot.ai"
            )
        default:
            return nil
        }
    }

    private func runDirectTest() async {
        await ProviderTestRunner.runTest(profile: profileForSave(), key: apiKey) { result in
            Task { @MainActor in
                self.testStatus = result.statusLabel
                if !result.models.isEmpty {
                    var seen = Set<String>()
                    let refreshed = result.models.filter { seen.insert($0).inserted }
                    self.modelList = refreshed
                    self.profile.availableModels = refreshed
                    if !refreshed.contains(self.profile.defaultModel) {
                        self.profile.defaultModel = refreshed.first ?? ""
                    }
                }
                self.testRunning = false
            }
        }
    }

    private func refreshModels() {
        guard !modelRefreshRunning else { return }
        modelRefreshRunning = true
        testStatus = nil
        let receive: @MainActor (ProviderTestRunner.Result) -> Void = { result in
            self.applyModelRefresh(result)
            self.modelRefreshRunning = false
        }
        if let onTest {
            onTest(profileForSave(), apiKey, receive)
        } else {
            Task {
                await ProviderTestRunner.runTest(profile: profileForSave(), key: apiKey) { result in
                    Task { @MainActor in receive(result) }
                }
            }
        }
    }

    @MainActor
    private func applyModelRefresh(_ result: ProviderTestRunner.Result) {
        var seen = Set<String>()
        let refreshed = result.models.filter { seen.insert($0).inserted }
        modelList = refreshed
        profile.availableModels = refreshed
        if refreshed.contains(profile.defaultModel) == false {
            profile.defaultModel = refreshed.first ?? ""
        }
        if refreshed.isEmpty, result.httpStatus.map({ (200..<300).contains($0) }) == true {
            testStatus = result.statusLabel + " · " + SidecarLocalizer.text("未返回模型目录，可手动输入模型 ID", "No model catalog was returned. Enter a model ID manually.")
        } else {
            testStatus = result.statusLabel
        }
    }

    private func profileForSave() -> ProviderProfile {
        var copy = profile
        copy.requestTimeout = min(max(copy.requestTimeout, 5), 300)
        copy.maxOutputTokens = min(max(copy.maxOutputTokens, 64), 128_000)
        copy.temperature = min(max(copy.temperature, 0), 2)
        var headers: [String: String] = [:]
        let blocked = Set(["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"])
        for rawLine in customHeadersText.components(separatedBy: .newlines) {
            guard let colon = rawLine.firstIndex(of: ":") else { continue }
            let name = rawLine[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawLine[rawLine.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty, !blocked.contains(name.lowercased()) else { continue }
            headers[name] = value
        }
        copy.customHeaders = headers
        return copy
    }

    private func addNewModel() {
        let m = newModelInput.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty else { return }
        if !modelList.contains(m) { modelList.append(m) }
        profile.defaultModel = m
        newModelInput = ""
    }

    private func testColor(_ s: String) -> Color {
        let normalized = s.lowercased()
        if s.contains("成功") || normalized.contains("connected") { return Tokens.Palette.statusSuccess(for: scheme) }
        if s.contains("失败") || s.contains("拒绝") || normalized.contains("failed") || normalized.contains("invalid") { return Tokens.Palette.statusError(for: scheme) }
        if s.contains("异常") || s.contains("限流") || normalized.contains("unexpected") || normalized.contains("rate limited") { return Tokens.Palette.statusWarning(for: scheme) }
        return Tokens.Palette.secondaryText(for: scheme)
    }
}
