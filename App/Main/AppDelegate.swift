import SwiftUI
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1) 启动核心服务
        MenuBarController.shared.install()
        SidecarPanelController.shared.install()
        GlobalHotKeys.shared.install()

        // 2) 异步引导
        Task { await AppModel.shared.bootstrap() }

        // 3) 默认隐藏 dock 图标
        NSApp.setActivationPolicy(.accessory)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 菜单栏常驻：所有窗口关闭后保持运行
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if AppModel.shared.historyRetention == .untilQuit {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                try? await ConversationStore.shared.deleteAllSessions()
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1.5)
        }
    }

    public func applicationDidResignActive(_ notification: Notification) {
        // 可选：不在 resign 时自动隐藏，避免误触
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        Task { await AppModel.shared.importPendingShare() }
    }
}
