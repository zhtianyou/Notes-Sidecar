import SwiftUI

/// 连续阅读面：用户问题使用轻量气泡，AI 回答直接落在内容面上。
struct ConversationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @ObservedObject private var state: ConversationState

    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
        self._state = ObservedObject(wrappedValue: model.session.state)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if state.turns.isEmpty {
                        QuickStartView(session: session)
                    }

                    ForEach(state.turns) { turn in
                        if turn.role == .user {
                            UserTurnRow(turn: turn)
                        } else if turn.role == .assistant {
                            AssistantTurnRow(
                                turn: turn,
                                events: state.events.filter { $0.turnId == turn.id },
                                model: model
                            )
                        }
                    }

                    Spacer(minLength: 12)
                        .id("__bottom")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: state.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            .onChange(of: state.lastAnswer) { _, _ in
                if case .generating = state.phase {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
        }
        .background(Color.clear)
    }
}

private struct QuickStartView: View {
    @ObservedObject var session: SessionController
    private let commands = ["summary", "tasks", "structure", "question"]
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("你想如何处理这篇笔记？")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                Text("选择一个动作，或直接在下方提问。")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(commands, id: \.self) { id in
                    if let command = SlashCommand.all.first(where: { $0.id == id }) {
                        Button {
                            Task { await session.execute(command) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: command.iconName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(commandColor(command))
                                    .frame(width: 30, height: 30)
                                    .background(commandColor(command).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(command.displayName))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                                    Text(LocalizedStringKey(shortHint(command)))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                                    .fill(Tokens.Palette.raisedSurface(for: scheme))
                                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(LocalizedStringKey(command.displayName))
                                + Text(": ")
                                + Text(LocalizedStringKey(command.promptHint))
                        )
                    }
                }
            }
        }
        .padding(.top, 26)
    }

    private func commandColor(_ command: SlashCommand) -> Color {
        Tokens.Palette.accent(for: scheme)
    }

    private func shortHint(_ command: SlashCommand) -> String {
        switch command.id {
        case "summary": return "保留事实与未决问题"
        case "tasks": return "任务、负责人、截止时间"
        case "structure": return "重组标题与段落"
        default: return "找出缺失信息"
        }
    }
}

private struct UserTurnRow: View {
    let turn: Turn
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        HStack {
            Spacer(minLength: 36)
            Text(turn.content)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Tokens.Palette.accent(for: scheme).opacity(scheme.isDark ? 0.13 : 0.10))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.Palette.accent(for: scheme).opacity(0.34), lineWidth: 1))
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("你：\(turn.content)")
    }
}

private struct AssistantTurnRow: View {
    let turn: Turn
    let events: [RunEvent]
    @ObservedObject var model: AppModel
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !events.isEmpty {
                RunEventPanel(events: events, isActive: turn.status == .streaming, model: model)
            }

            if turn.status == .failed, let message = turn.errorMessage {
                ErrorRecoveryCard(message: message, model: model)
            } else {
                if turn.content.isEmpty && turn.status == .streaming {
                    GeneratingIndicator()
                } else if !turn.content.isEmpty {
                    MarkdownContentView(content: turn.content)
                }

                if turn.status == .cancelled {
                    HStack(spacing: 8) {
                        Label("已停止 · 已生成内容保留在本机", systemImage: "stop.circle")
                        Spacer(minLength: 4)
                        Button("用最新内容重试") {
                            Task { await model.session.retryLastQuestion() }
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Tokens.Palette.statusFill(for: .warning, scheme: scheme), in: RoundedRectangle(cornerRadius: 10))
                }

                if turn.status == .completed || turn.status == .cancelled {
                    answerActions
                }
            }

            if let meta = metadata {
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if !turn.content.isEmpty {
                Button(model.interfaceText("复制回答", "Copy Response")) {
                    model.copyAnswer(turn.content)
                }
            }
        }
    }

    private var answerActions: some View {
        HStack(spacing: 7) {
            AnswerAction(title: "复制", icon: "doc.on.doc", model: model) {
                model.copyAnswer(turn.content)
            }
            AnswerAction(title: "插入备忘录", icon: "text.append", tint: Tokens.Palette.agentMint(for: scheme), model: model) {
                Task { await model.appendAnswer(turn.content) }
            }
            AnswerAction(title: "新建笔记", icon: "note.text.badge.plus", tint: Tokens.Palette.contextAmber(for: scheme), model: model) {
                Task { await model.createNote(from: turn.content) }
            }
        }
        .padding(.top, 2)
    }

    private var metadata: String? {
        var parts: [String] = []
        if let model = turn.model, !model.isEmpty { parts.append(model) }
        if let duration = turn.durationMs { parts.append(String(format: "%.1f s", Double(duration) / 1000)) }
        if let output = turn.outputTokens { parts.append("\(output) tokens") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// SwiftUI 的 `AttributedString(markdown:)` 仅可靠处理行内标记；这里补齐笔记回答常见的块级结构。
struct MarkdownContentView: View {
    let content: String
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlock.parse(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 18 : level == 2 ? 16 : 14, weight: .semibold))
                .padding(.top, level == 1 ? 2 : 5)
        case let .paragraph(text):
            Text(inline(text))
                .font(.system(size: Tokens.Font.answer))
                .lineSpacing(5)
        case let .list(items, orderedStart):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(orderedStart.map { "\($0 + index)." } ?? "•")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
                            .frame(width: 19, alignment: .trailing)
                        Text(inline(item))
                            .font(.system(size: Tokens.Font.answer))
                            .lineSpacing(4)
                    }
                }
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Tokens.Palette.accent(for: scheme).opacity(0.78))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.system(size: Tokens.Font.answer))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
            }
            .padding(.vertical, 4)
        case let .code(text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                    .padding(12)
            }
            .background(Tokens.Palette.insetSurface(for: scheme), in: RoundedRectangle(cornerRadius: 10))
        case let .table(rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                                .font(.system(size: 11, weight: rowIndex == 0 ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(rowIndex == 0 ? Tokens.Palette.controlFill(for: scheme) : Color.clear)
                    if rowIndex < rows.count - 1 {
                        Divider().overlay(Tokens.Palette.separator(for: scheme))
                    }
                }
            }
            .background(Tokens.Palette.insetSurface(for: scheme).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
        }
    }

    private func inline(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(items: [String], orderedStart: Int?)
    case quote(String)
    case code(String)
    case table([[String]])

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }

            if line.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: line) {
                blocks.append(.heading(level: heading.0, text: heading.1)); index += 1; continue
            }

            if isTableHeader(at: index, lines: lines) {
                var rows = [tableCells(lines[index])]
                index += 2
                while index < lines.count, lines[index].contains("|") {
                    let cells = tableCells(lines[index])
                    if cells.isEmpty { break }
                    rows.append(cells); index += 1
                }
                blocks.append(.table(rows)); continue
            }

            if line.hasPrefix(">") {
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); index += 1; continue
            }

            if let item = unorderedItem(line) {
                var items = [item]; index += 1
                while index < lines.count, let next = unorderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next); index += 1
                }
                blocks.append(.list(items: items, orderedStart: nil)); continue
            }

            if let item = orderedItem(line) {
                let start = item.number
                var items = [item.text]; index += 1
                while index < lines.count, let next = orderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next.text); index += 1
                }
                blocks.append(.list(items: items, orderedStart: start)); continue
            }

            var paragraph = [line]; index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || heading(from: next) != nil || next.hasPrefix("```") || next.hasPrefix(">") || unorderedItem(next) != nil || orderedItem(next) != nil || isTableHeader(at: index, lines: lines) { break }
                paragraph.append(next); index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }

    private static func heading(from line: String) -> (Int, String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes + 1).description)
    }

    private static func unorderedItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let number = line[..<dot]
        let rest = line[line.index(after: dot)...]
        guard number.allSatisfy(\.isNumber), let value = Int(number), rest.first == " " else { return nil }
        return (value, String(rest.dropFirst()))
    }

    private static func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separator = lines[index + 1].replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return separator.isEmpty && lines[index + 1].contains("-")
    }

    private static func tableCells(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct RunEventPanel: View {
    let events: [RunEvent]
    let isActive: Bool
    @ObservedObject var model: AppModel
    @State private var expanded = false
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isActive ? "waveform" : summaryIcon)
                        .foregroundStyle(summaryColor)
                    Text(model.localized(summaryText))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                    Spacer()
                    Text(model.localizedFormat("%lld 步", events.count))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tokens.Palette.accent(for: scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Tokens.Palette.accent(for: scheme).opacity(0.12), in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)

            if expanded || isActive {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events.sorted(by: { $0.sequence < $1.sequence })) { event in
                        RunEventRow(event: event, isLast: event.id == events.last?.id, model: model)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Tokens.Palette.insetSurface(for: scheme).opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))
        )
    }

    private var summaryText: String {
        if isActive { return events.last?.label ?? "正在处理" }
        if events.contains(where: { $0.type == .failed }) { return "运行失败" }
        if events.contains(where: { $0.type == .cancelled }) { return "运行已停止" }
        let total = events.compactMap(\.durationMs).reduce(0, +)
        return total > 0 ? model.localizedFormat("完成 · %.1f 秒", Double(total) / 1000) : "完成"
    }

    private var summaryIcon: String {
        events.contains(where: { $0.type == .failed }) ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var summaryColor: Color {
        if events.contains(where: { $0.type == .failed }) { return Tokens.Palette.statusError(for: scheme) }
        if events.contains(where: { $0.type == .cancelled }) { return Tokens.Palette.statusWarning(for: scheme) }
        return Tokens.Palette.agentMint(for: scheme)
    }
}

private struct RunEventRow: View {
    let event: RunEvent
    let isLast: Bool
    @ObservedObject var model: AppModel
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(eventColor.opacity(0.22))
                    .overlay(Circle().stroke(eventColor.opacity(0.72), lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .overlay(Image(systemName: event.type.iconSystemName).font(.system(size: 8, weight: .bold)).foregroundStyle(eventColor))
                if !isLast {
                    Rectangle().fill(eventColor.opacity(0.24)).frame(width: 1, height: 20)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.localized(event.label))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                if let detail = event.redactedSummary, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if let duration = event.durationMs {
                Text("\(duration) ms")
                    .font(.system(size: 9))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
            }
        }
        .frame(minHeight: 28)
    }

    private var eventColor: Color {
        switch event.status {
        case .error: return Tokens.Palette.statusError(for: scheme)
        case .warning: return Tokens.Palette.statusWarning(for: scheme)
        case .running: return Tokens.Palette.accent(for: scheme)
        case .ok: return Tokens.Palette.agentMint(for: scheme)
        case .info: return Tokens.Palette.accent(for: scheme)
        }
    }
}

private struct GeneratingIndicator: View {
    @State private var pulsing = false
    @Environment(\.sidecarTheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Tokens.Palette.agentMint(for: scheme))
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.0 : 0.62)
                .opacity(pulsing ? 1.0 : 0.42)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            Text("正在组织回答…")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
        }
        .onAppear { pulsing = true }
    }
}

private struct ErrorRecoveryCard: View {
    let message: String
    @ObservedObject var model: AppModel
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tokens.Palette.statusError(for: scheme))
            VStack(alignment: .leading, spacing: 4) {
                Text("回答未完成")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if isRetryable {
                        Button("重试") { Task { await model.session.retryLastQuestion() } }
                    }
                    Button(needsSettings ? "检查服务商" : "打开设置") { model.openSettings() }
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.statusError(for: scheme).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.Palette.statusError(for: scheme).opacity(0.24), lineWidth: 1))
    }

    private var isRetryable: Bool {
        let text = message.lowercased()
        return text.contains("网络") || text.contains("超时") || text.contains("频繁") || text.contains("限流") || text.contains("中断") ||
            text.contains("network") || text.contains("timed out") || text.contains("too many") || text.contains("rate limit") || text.contains("interrupted")
    }

    private var needsSettings: Bool {
        let text = message.lowercased()
        return message.contains("Key") || message.contains("密钥") || message.contains("模型") || message.contains("配置") ||
            text.contains("api key") || text.contains("model") || text.contains("configuration") || text.contains("endpoint")
    }
}

private struct AnswerAction: View {
    let title: String
    let icon: String
    var tint: Color?
    @ObservedObject var model: AppModel
    let action: () -> Void
    @Environment(\.sidecarTheme) private var scheme

    init(title: String, icon: String, tint: Color? = nil, model: AppModel, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.model = model
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(model.localized(title), systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(resolvedTint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Tokens.Palette.controlFill(for: scheme), in: Capsule())
                .overlay(Capsule().stroke(resolvedTint.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var resolvedTint: Color {
        tint ?? Tokens.Palette.secondaryText(for: scheme)
    }
}
