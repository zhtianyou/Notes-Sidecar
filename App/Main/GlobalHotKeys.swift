import SwiftUI
import AppKit
import Carbon.HIToolbox

/// 全局快捷键注册（Carbon）。注册后通过闭包回调到 MainActor。
@MainActor
public final class GlobalHotKeys {
    public static let shared = GlobalHotKeys()

    /// `handlers` 在 Carbon 回调（非 MainActor）里读，所以必须独立锁保护。
    /// Sendable 包装保证 `unowned` 闭包能安全捕获。
    private final class HandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _handlers: [UInt32: @MainActor @Sendable () -> Void] = [:]
        func set(_ key: UInt32, _ action: @escaping @MainActor @Sendable () -> Void) {
            lock.lock(); _handlers[key] = action; lock.unlock()
        }
        func get(_ key: UInt32) -> (@MainActor @Sendable () -> Void)? {
            lock.lock(); defer { lock.unlock() }
            return _handlers[key]
        }
    }
    private let handlersBox = HandlerBox()
    private var registeredIDs: [EventHotKeyID] = []
    private var eventHandler: EventHandlerRef?

    public init() {}

    public func install() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passRetained(handlersBox).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let box = Unmanaged<HandlerBox>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                if let action = box.get(id) {
                    Task { @MainActor in action() }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
        register(id: 1, keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), action: { AppModel.shared.togglePanelVisibility() })
        // ⌘K 留作 Command Palette（按设计图 11），不再占位开设置。
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor @Sendable () -> Void) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x5344_4944 /* 'SDID' */), id: id)
        let ref = UnsafeMutablePointer<EventHotKeyRef?>.allocate(capacity: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, ref)
        guard status == noErr else { return }
        handlersBox.set(id, action)
        registeredIDs.append(hotKeyID)
    }

    public func uninstall() {
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }
}