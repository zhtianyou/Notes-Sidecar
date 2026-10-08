import SwiftUI
import AppKit
import ApplicationServices

/// 唯一 Sidecar 主窗口的控制器：支持 docked / independent / compact
/// 三种模式，并负责菜单栏的显示/隐藏。
@MainActor
public final class SidecarPanelController: NSObject, NSWindowDelegate {
    public static let shared = SidecarPanelController()

    private var panel: NSPanel?
    private var hosting: NSHostingController<RootView>?
    private var followTask: Task<Void, Never>?

    public override init() { super.init() }

    public func install() {
        guard panel == nil else { return }
        let mode = AppModel.shared.windowMode
        let size = mode.defaultSize
        let frame = NSRect(origin: defaultOrigin(for: size), size: size)
        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "Notes Sidecar"
        // 保留独立的系统标题栏，整行都可作为稳定拖拽区域。内容不再延伸到
        // 交通灯背后，避免透明桌面让窗口边界难以识别。
        newPanel.titlebarAppearsTransparent = false
        newPanel.titlebarSeparatorStyle = .line
        newPanel.isMovableByWindowBackground = true
        newPanel.isOpaque = false
        newPanel.backgroundColor = Self.chromeColor(
            for: AppModel.shared.appearanceMode,
            effectiveAppearance: newPanel.effectiveAppearance
        )
        newPanel.hasShadow = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        newPanel.hidesOnDeactivate = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        newPanel.minSize = CGSize(width: 360, height: 480)
        newPanel.maxSize = CGSize(width: 900, height: 1200)
        newPanel.delegate = self
        newPanel.isReleasedWhenClosed = false

        let host = NSHostingController(rootView: RootView(model: AppModel.shared))
        host.view.frame = newPanel.contentView?.bounds ?? .zero
        host.view.autoresizingMask = [.width, .height]
        newPanel.contentView?.addSubview(host.view)
        hosting = host
        panel = newPanel

        applyPinnedState(to: newPanel)
        newPanel.orderFront(nil)
        AppModel.shared.isPanelVisible = true
        preferencesDidChange()
    }

    public func syncVisibility(bringToFront: Bool = false) {
        guard let panel else { install(); return }
        if AppModel.shared.isPanelVisible {
            if panel.isVisible == false {
                if let origin = AppModel.shared.panelCenter {
                    panel.setFrameOrigin(origin)
                } else {
                    panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
                }
            }
            if panel.isMiniaturized { panel.deminiaturize(nil) }
            if bringToFront {
                // `nonactivatingPanel` keeps normal sidecar interaction from
                // stealing focus from Notes. An explicit Open command is the
                // exception: activate once and make the panel key. Its level
                // remains `.normal` when unpinned, so another app can cover it
                // again as expected.
                NSApp.activate(ignoringOtherApps: true)
                panel.orderFrontRegardless()
                panel.makeKey()
            } else if AppModel.shared.isPinned {
                panel.orderFrontRegardless()
            } else {
                panel.orderFront(nil)
            }
        } else {
            panel.orderOut(nil)
        }
    }

    public func setMode(_ mode: AppModel.WindowMode) {
        AppModel.shared.windowMode = mode
        guard let panel else { return }
        let size = mode.defaultSize
        var f = panel.frame
        f.origin.x += f.size.width - size.width
        f.origin.y += f.size.height - size.height
        f.size = size
        panel.setFrame(f, display: true, animate: true)
        AppModel.shared.updatePreferences()
        if mode == .docked { positionBesideNotesIfPossible() }
    }

    public func preferencesDidChange() {
        switch AppModel.shared.appearanceMode {
        case .system:
            panel?.appearance = nil
        case .dark:
            panel?.appearance = NSAppearance(named: .darkAqua)
        case .light:
            panel?.appearance = NSAppearance(named: .aqua)
        case .technology:
            panel?.appearance = NSAppearance(named: .darkAqua)
        }
        if let panel {
            panel.backgroundColor = Self.chromeColor(
                for: AppModel.shared.appearanceMode,
                effectiveAppearance: panel.effectiveAppearance
            )
            applyPinnedState(to: panel)
        }
        followTask?.cancel()
        followTask = nil
        guard AppModel.shared.followNotesWindow,
              AppModel.shared.windowMode == .docked else { return }
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.positionBesideNotesIfPossible()
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }

    public func applyPinnedState() {
        guard let panel else { return }
        applyPinnedState(to: panel)
        if AppModel.shared.isPinned, panel.isVisible { panel.orderFrontRegardless() }
    }

    private func applyPinnedState(to panel: NSPanel) {
        let pinned = AppModel.shared.isPinned
        panel.isFloatingPanel = pinned
        panel.level = pinned ? .floating : .normal
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let s = screen else { return CGPoint(x: 100, y: 100) }
        let vf = s.visibleFrame
        var x = vf.maxX - size.width - 16
        var y = vf.midY - size.height / 2
        x = max(vf.minX + 16, min(x, vf.maxX - size.width - 16))
        y = max(vf.minY + 16, min(y, vf.maxY - size.height - 16))
        return CGPoint(x: x, y: y)
    }

    private nonisolated static func chromeColor(
        for mode: AppModel.AppearanceMode,
        effectiveAppearance: NSAppearance
    ) -> NSColor {
        switch mode {
        case .light:
            return NSColor(calibratedRed: 237/255, green: 243/255, blue: 246/255, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 26/255, alpha: 1)
        case .technology:
            return NSColor(calibratedRed: 13/255, green: 24/255, blue: 33/255, alpha: 1)
        case .system:
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 26/255, alpha: 1)
                : NSColor(calibratedRed: 237/255, green: 243/255, blue: 246/255, alpha: 1)
        }
    }

    private func positionBesideNotesIfPossible() {
        guard AXIsProcessTrusted(), let panel, panel.isVisible,
              let notes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first,
              let noteFrame = Self.frontWindowFrame(pid: notes.processIdentifier) else { return }

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(noteFrame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let gap: CGFloat = 14
        let rightX = noteFrame.maxX + gap
        let leftX = noteFrame.minX - panel.frame.width - gap
        var x = AppModel.shared.dockSide == .right ? rightX : leftX
        if x + panel.frame.width > visible.maxX { x = leftX }
        if x < visible.minX { x = rightX }
        x = min(max(x, visible.minX), visible.maxX - panel.frame.width)
        let y = min(max(noteFrame.maxY - panel.frame.height, visible.minY), visible.maxY - panel.frame.height)
        let target = CGPoint(x: x, y: y)
        if abs(panel.frame.origin.x - target.x) > 1 || abs(panel.frame.origin.y - target.y) > 1 {
            panel.setFrameOrigin(target)
        }
    }

    private nonisolated static func frontWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], let window = windows.first else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else { return nil }
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? size.height
        return CGRect(x: position.x, y: primaryTop - position.y - size.height, width: size.width, height: size.height)
    }

    // MARK: NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) {
        AppModel.shared.isPanelVisible = true
    }

    public func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === panel else { return }
        AppModel.shared.panelCenter = window.frame.origin
    }

    public func windowWillClose(_ notification: Notification) {
        AppModel.shared.isPanelVisible = false
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        if AppModel.shared.closeBehavior == .quit {
            NSApp.terminate(nil)
        } else {
            sender.orderOut(nil)
            AppModel.shared.isPanelVisible = false
        }
        return false
    }
}
