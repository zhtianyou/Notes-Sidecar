import SwiftUI
import AppKit

/// 顶部上下文栏：笔记身份、同步状态与低频操作。
struct HeaderBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @Environment(\.sidecarTheme) private var scheme

    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Tokens.Palette.accent(for: scheme).opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Tokens.Palette.accent(for: scheme).opacity(0.34), lineWidth: 1))
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.noteContext?.locator.titleSnapshot ?? "Ask this note")
                        .font(.system(size: Tokens.Font.headerTitle, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.primaryText(for: scheme))
                        .lineLimit(1)
                    Text(headerSubtitle)
                        .font(.system(size: Tokens.Font.meta))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    model.togglePinned()
                } label: {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.isPinned ? Tokens.Palette.agentMint(for: scheme) : Tokens.Palette.secondaryText(for: scheme))
                .help(model.isPinned ? "取消置顶" : "置顶窗口")
                .accessibilityLabel(model.isPinned ? "取消置顶窗口" : "置顶窗口")

                Button {
                    model.isHistoryPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                .help("当前笔记的对话历史")
                .accessibilityLabel("打开对话历史")

                Menu {
                    Button("刷新当前笔记", systemImage: "arrow.clockwise") {
                        Task { await model.refreshContext() }
                    }
                    Divider()
                    Menu("窗口模式") {
                        ForEach(AppModel.WindowMode.allCases) { mode in
                            Button(LocalizedStringKey(mode.label)) { SidecarPanelController.shared.setMode(mode) }
                        }
                    }
                    Button("清空当前对话…", systemImage: "trash", role: .destructive) {
                        model.isClearConversationConfirmationPresented = true
                    }
                    .disabled(session.state.turns.isEmpty)
                    Divider()
                    Button {
                        model.openSettings()
                    } label: {
                        Label("设置…", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("更多操作")
                .accessibilityLabel("更多操作")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(level: .chrome, corner: Tokens.Radius.panel)
    }

    private var headerSubtitle: String {
        switch session.state.phase {
        case .generating: return model.localized("正在生成")
        case .paused: return model.localized("生成已停止，内容已保留")
        case .retrying(let attempt): return model.localizedFormat("第 %lld 次重试", attempt)
        case .error: return model.localized("需要处理后继续")
        case .idle:
            if let banner = model.statusBanner { return banner }
            if session.noteContext != nil { return model.localized("已同步") }
            return model.localized("等待连接备忘录")
        }
    }

    private var subtitleColor: Color {
        switch session.state.phase {
        case .generating: return Tokens.Palette.agentMint(for: scheme)
        case .paused, .retrying: return Tokens.Palette.statusWarning(for: scheme)
        case .error: return Tokens.Palette.statusError(for: scheme)
        case .idle: return Tokens.Palette.secondaryText(for: scheme)
        }
    }

}

struct ConversationHistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: SessionController
    @ObservedObject private var state: ConversationState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidecarTheme) private var scheme
    @State private var query = ""
    @State private var confirmClear = false

    init(model: AppModel) {
        self.model = model
        self._session = ObservedObject(wrappedValue: model.session)
        self._state = ObservedObject(wrappedValue: model.session.state)
    }

    private var filteredTurns: [Turn] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return state.turns }
        return state.turns.filter { $0.content.localizedCaseInsensitiveContains(text) }
    }

    private var dayGroups: [(day: Date, turns: [Turn])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredTurns) { calendar.startOfDay(for: $0.createdAt) }
            .map { (day: $0.key, turns: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("对话历史")
                        .font(.system(size: 17, weight: .semibold))
                    Text(session.noteContext?.locator.titleSnapshot ?? "当前笔记")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(state.turns.count) 条")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
                Button("完成") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(18)

            Divider().overlay(Tokens.Palette.separator(for: scheme))

            if state.turns.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("这篇笔记还没有对话")
                        .font(.system(size: 13, weight: .medium))
                    Text("关闭历史后，在输入框中提出第一个问题。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.turns) { turn in
                                historyRow(turn)
                                    .contextMenu {
                                        if turn.role == .user {
                                            Button("从这一问重新生成", systemImage: "arrow.clockwise") {
                                                Task { await session.regenerate(from: turn) }
                                            }
                                        }
                                        Button("删除这一条", systemImage: "trash", role: .destructive) {
                                            Task { await session.deleteTurn(turn) }
                                        }
                                        Button("删除这一条及之后内容", systemImage: "text.badge.minus", role: .destructive) {
                                            Task { await session.deleteFromTurn(turn) }
                                        }
                                    }
                            }
                        } header: {
                            Text(group.day, format: .dateTime.year().month().day())
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Tokens.Palette.contentSurface(for: scheme))
                .searchable(text: $query, prompt: "搜索问题和回答")
            }

            Divider().overlay(Tokens.Palette.separator(for: scheme))
            HStack {
                Button {
                    model.exportCurrentConversation()
                } label: {
                    Label("导出 Markdown…", systemImage: "square.and.arrow.up")
                }
                .disabled(state.turns.isEmpty)

                Spacer()

                Button("清空对话…", role: .destructive) {
                    confirmClear = true
                }
                .disabled(state.turns.isEmpty)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(16)
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 520)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
        .confirmationDialog(
            "清空当前对话？",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("清空对话", role: .destructive) {
                Task { await model.clearCurrentConversation() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除这篇笔记在 Sidecar 中的问题、回答和运行记录，不会删除或修改 Notes 原文。")
        }
    }

    private func historyRow(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(turn.role.displayLabel, systemImage: turn.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(turn.role == .user ? Tokens.Palette.contextAmber(for: scheme) : Tokens.Palette.agentMint(for: scheme))
                Spacer()
                Text(turn.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text(turn.content.isEmpty ? "生成未完成" : turn.content)
                .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.82))
                .lineLimit(4).textSelection(.enabled)
        }
        .padding(.vertical, 6).listRowBackground(Color.clear)
    }
}
