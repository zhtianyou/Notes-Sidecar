import AppKit
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: ShareText.text("正在准备内容…", "Preparing content…"))
    private let saveButton = NSButton(title: ShareText.text("发送到 Sidecar", "Send to Sidecar"), target: nil, action: nil)
    private var sharedText = ""

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: ShareText.text("取消", "Cancel"), target: self, action: #selector(cancel))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel); root.addSubview(saveButton); root.addSubview(cancel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            statusLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            saveButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            cancel.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadSharedContent()
    }

    private func loadSharedContent() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { statusLabel.stringValue = ShareText.text("没有可发送的文字内容。", "There is no text to send."); return }
        let group = DispatchGroup()
        let fragments = FragmentCollector()
        for provider in providers {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                ? UTType.plainText.identifier
                : provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : nil
            guard let type else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                let text: String?
                if let value = item as? String { text = value }
                else if let url = item as? URL { text = url.absoluteString }
                else if let data = item as? Data { text = String(data: data, encoding: .utf8) }
                else { text = nil }
                if let text, !text.isEmpty { fragments.append(text) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.sharedText = fragments.joined()
            self.statusLabel.stringValue = self.sharedText.isEmpty
                ? ShareText.text("没有可发送的文字内容。", "There is no text to send.")
                : ShareText.text("已准备 \(self.sharedText.count) 个字符。内容将保存到本机 Sidecar 收件箱。", "Prepared \(self.sharedText.count) characters. The content will be saved to the local Sidecar inbox.")
            self.saveButton.isEnabled = !self.sharedText.isEmpty
        }
    }

    @objc private func save() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.youwin.NotesSidecar") else {
            statusLabel.stringValue = ShareText.text("共享容器尚未配置。正式签名时需要启用 App Group。", "The shared container is not configured. Enable App Groups for the release signing configuration.")
            return
        }
        let inbox = container.appendingPathComponent("ShareInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let payload = Payload(id: UUID(), title: ShareText.text("从 Notes 分享", "Shared from Notes"), text: sharedText, createdAt: Date())
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload).write(to: inbox.appendingPathComponent("\(payload.id.uuidString).json"), options: .atomic)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.stringValue = ShareText.text("保存失败：\(error.localizedDescription)", "Could not save: \(error.localizedDescription)")
        }
    }

    @objc private func cancel() { extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
}

private enum ShareText {
    static func text(_ simplifiedChinese: String, _ english: String) -> String {
        let defaults = UserDefaults(suiteName: "group.com.youwin.NotesSidecar")
        let preference = defaults?.string(forKey: "interfaceLanguage") ?? "automatic"
        if preference == "simplifiedChinese" { return simplifiedChinese }
        if preference == "english" { return english }
        let language = Locale.preferredLanguages.first?.replacingOccurrences(of: "_", with: "-").lowercased() ?? "en"
        return language == "zh" || (language.hasPrefix("zh-") && !language.contains("hant") && !language.hasPrefix("zh-tw") && !language.hasPrefix("zh-hk"))
            ? simplifiedChinese : english
    }
}

/// `NSItemProvider` may invoke completion handlers concurrently. Keeping the
/// mutable collection behind a lock also satisfies Swift 6 strict concurrency.
private final class FragmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.joined(separator: "\n\n")
    }
}

private struct Payload: Codable {
    let id: UUID
    let title: String
    let text: String
    let createdAt: Date
}
