import SwiftUI
import AppKit

/// 菜单栏图标 + 下拉菜单
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var menu: NSMenu?

    public override init() { super.init() }

    public func install() {
        if item != nil { return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = status.button {
            btn.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Notes Sidecar")
            btn.image?.isTemplate = true
        }
        status.menu = buildMenu()
        item = status
    }

    /// NSMenu does not observe SwiftUI's locale environment. Rebuild it whenever
    /// the in-app language preference changes so the menu bar never gets stuck
    /// in the launch language.
    public func refreshLocalizedMenu() {
        guard let item else { return }
        item.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: AppModel.shared.localized("打开边栏"), action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppModel.shared.localized("刷新当前笔记"), action: #selector(refreshContext), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: AppModel.shared.localized("设置…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: AppModel.shared.localized("退出"), action: #selector(quitApp), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func showPanel() { AppModel.shared.showPanel() }
    @objc private func refreshContext() { Task { await AppModel.shared.refreshContext() } }
    @objc private func openSettings() { AppModel.shared.openSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
