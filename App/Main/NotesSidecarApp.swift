import SwiftUI
import AppKit

@main
struct NotesSidecarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model: AppModel = AppModel.shared

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        // The Sidecar surface is the singleton NSPanel owned by
        // SidecarPanelController. Declaring a Window/WindowGroup here creates a
        // second copy of RootView, so this App scene owns settings only.
        Settings {
            SettingsView(model: model)
                .frame(minWidth: 700, minHeight: 540)
                .environment(\.locale, model.interfaceLocale)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(model.localized("设置…")) { model.openSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) { }
            SidecarCommands(model: model)
        }
    }
}

struct SidecarCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Sidecar") {
            Button(model.localized("命令面板…")) { model.openCommandPalette() }
                .keyboardShortcut("k", modifiers: [.command])
            Divider()
            Button(model.localized("显示 / 隐藏 Sidecar")) { model.togglePanelVisibility() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button(model.localized("刷新当前笔记")) { Task { await model.refreshContext() } }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button(model.localized("发送")) { Task { await model.sendFromMenu() } }
                .keyboardShortcut(.return, modifiers: [.command])
            Button(model.localized("停止生成")) { model.stopFromMenu() }
                .keyboardShortcut(".", modifiers: [.command])
            Divider()
            Button(model.localized("复制最后回答")) { model.copyLastAnswer() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(model.localized("追加最后回答")) { Task { await model.appendLastAnswer() } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button(model.localized("执行默认写回")) { Task { await model.performDefaultWriteback() } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Menu(model.localized("窗口模式")) {
                ForEach(AppModel.WindowMode.allCases) { m in
                    Button(model.localized(m.label)) { SidecarPanelController.shared.setMode(m) }
                }
            }
        }
    }
}
