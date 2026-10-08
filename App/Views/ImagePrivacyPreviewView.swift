import SwiftUI

/// 发送前的本机图片识别确认。这里只展示放行文本和命中类别，
/// 不展示、持有或上传原图与被排除的 OCR 原文。
struct ImagePrivacyPreviewView: View {
    @ObservedObject var model: AppModel
    let candidate: AppModel.PendingImageImport
    @Environment(\.sidecarTheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: candidate.containsPrivateContent ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(candidate.containsPrivateContent ? Tokens.Palette.statusWarning(for: scheme) : Tokens.Palette.agentMint(for: scheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.containsPrivateContent ? "识别到隐私内容" : "本机识别完成")
                        .font(.system(size: 16, weight: .semibold))
                    Text(candidate.fileName)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                }
            }

            if candidate.privacyScanFailed {
                Text("隐私检查未完成。为避免泄漏，任何图片识别内容都不会提交给 AI。")
                    .foregroundStyle(Tokens.Palette.statusError(for: scheme))
            } else if candidate.containsPrivateContent {
                Text(model.localizedFormat("检测到隐私内容，已排除 %lld 行。被排除的部分和图片原图都不会提交给 AI。", candidate.excludedLineCount))
                    .foregroundStyle(Tokens.Palette.statusWarning(for: scheme))
                if !candidate.findingLabels.isEmpty {
                    Text(model.interfaceText("检测类型：\(candidate.findingLabels.joined(separator: "、"))", "Detected: \(candidate.findingLabels.joined(separator: ", "))"))
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                }
            } else {
                Text("未检测到隐私内容。图片原图不会上传；确认后下面的安全文字只作为对话上下文，不会填入输入框。")
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("将作为对话上下文的内容")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.secondaryText(for: scheme))
                ScrollView {
                    Text(candidate.safeText.isEmpty ? "没有可安全提交的识别内容" : candidate.safeText)
                        .font(.system(size: 12))
                        .foregroundStyle(candidate.safeText.isEmpty ? Tokens.Palette.tertiaryText(for: scheme) : Tokens.Palette.primaryText(for: scheme))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 150, maxHeight: 260)
                .background(Tokens.Palette.insetSurface(for: scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.Palette.separator(for: scheme)))
            }

            HStack {
                Text(model.localizedFormat("共识别 %lld 项", candidate.recognizedLineCount))
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.tertiaryText(for: scheme))
                Spacer()
                Button("取消") { model.cancelImageImport() }
                Button(candidate.containsPrivateContent ? "使用安全内容" : "添加图片上下文") {
                    model.confirmImageImport(candidate)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate.privacyScanFailed || candidate.safeText.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        .background(Tokens.Palette.dialogGlassSurface(for: scheme).ignoresSafeArea())
        .presentationBackground(Tokens.Palette.dialogGlassSurface(for: scheme))
    }
}
