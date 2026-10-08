import SwiftUI

/// Append 的确认边界：真正写入前再次校验 Notes 快照，冲突时保持结果不丢失。
struct WritebackPreviewView: View {
    @ObservedObject var model: AppModel
    let initialPlan: ResultWriter.AppendPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidecarTheme) private var scheme
    @State private var isWriting = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var canRefreshConflict = false

    private var plan: ResultWriter.AppendPlan {
        guard let pending = model.pendingAppendPlan, pending.id == initialPlan.id else { return initialPlan }
        return pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.append")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))
                    .frame(width: 34, height: 34)
                    .background(Tokens.Palette.contextAmber(for: scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("追加到备忘录")
                        .font(.system(size: 17, weight: .semibold))
                    Text("将把以下内容追加到「\(plan.source.locator.titleSnapshot)」末尾")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Label("\(plan.preview.expectedAppendChars) 字", systemImage: "character.cursor.ibeam")
                Label("写入前检查版本", systemImage: "checkmark.shield")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Tokens.Palette.contextAmber(for: scheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Divider().overlay(Tokens.Palette.separator(for: scheme))
                    Label(plan.preview.title, systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.agentMint(for: scheme))
                    MarkdownContentView(content: plan.answer)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(minHeight: 210, maxHeight: 360)
            .background(Tokens.Palette.insetSurface(for: scheme).opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.Palette.separator(for: scheme), lineWidth: 1))

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(errorMessage, systemImage: canRefreshConflict ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(canRefreshConflict ? Tokens.Palette.statusWarning(for: scheme) : Tokens.Palette.statusError(for: scheme))
                    if canRefreshConflict {
                        Text("回答仍保留在本机。重新预览后才能写入最新版本。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((canRefreshConflict ? Tokens.Palette.statusWarning(for: scheme) : Tokens.Palette.statusError(for: scheme)).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Label("这是写入后的富文本效果；尚未修改 Notes。确认时会再次检查正文版本。", systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("取消", role: .cancel) {
                    model.cancelAppend()
                    dismiss()
                }

                Spacer()

                if canRefreshConflict {
                    Button {
                        refreshPreview()
                    } label: {
                        if isRefreshing { ProgressView().controlSize(.small) }
                        else { Text("使用最新版本重新预览") }
                    }
                    .disabled(isRefreshing)
                } else {
                    Button {
                        confirm()
                    } label: {
                        if isWriting { ProgressView().controlSize(.small) }
                        else { Text("确认追加") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWriting)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 470)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
        .interactiveDismissDisabled(isWriting || isRefreshing)
        .onExitCommand {
            guard !isWriting, !isRefreshing else { return }
            model.cancelAppend()
            dismiss()
        }
        .onDisappear {
            if !isWriting {
                model.cancelAppend()
            }
        }
    }

    private func confirm() {
        isWriting = true
        errorMessage = nil
        Task {
            do {
                try await model.confirmAppend(plan)
                dismiss()
            } catch let conflict as ResultWriter.SafeAppendError {
                errorMessage = conflict.localizedDescription
                canRefreshConflict = true
            } catch {
                errorMessage = "写入失败：\(error.localizedDescription)"
                canRefreshConflict = false
            }
            isWriting = false
        }
    }

    private func refreshPreview() {
        isRefreshing = true
        Task {
            do {
                try await model.rebaseAppendPlan(plan)
                errorMessage = nil
                canRefreshConflict = false
            } catch {
                errorMessage = error.localizedDescription
                canRefreshConflict = error is ResultWriter.SafeAppendError
            }
            isRefreshing = false
        }
    }
}
