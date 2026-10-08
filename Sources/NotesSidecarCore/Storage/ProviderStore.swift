import Foundation

public actor ProviderStore {
    public static let shared = ProviderStore()

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.url = dir.appendingPathComponent("providers.json")
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]; enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    private static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let app = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = app.appendingPathComponent("NotesSidecar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func load() async -> [ProviderProfile] {
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([ProviderProfile].self, from: data) else { return [] }
        return list
    }

    public func all() async -> [ProviderProfile] { await load() }

    public func get(_ id: String) async -> ProviderProfile? {
        (await load()).first(where: { $0.id == id })
    }

    public func upsert(_ profile: ProviderProfile) async throws {
        var list = await load()
        if let idx = list.firstIndex(where: { $0.id == profile.id }) {
            var p = profile; p.updatedAt = Date()
            list[idx] = p
        } else {
            list.append(profile)
        }
        let data = try encoder.encode(list)
        try data.write(to: url, options: [.atomic])
    }

    public func delete(_ id: String) async throws {
        var list = await load()
        list.removeAll { $0.id == id }
        let data = try encoder.encode(list)
        try data.write(to: url, options: [.atomic])
        try? await KeychainStore.shared.delete(ref: "provider.\(id).credential")
        try? await KeychainStore.shared.delete(ref: "provider.\(id).chatgpt-oauth")
    }

    public func defaultProfile() async -> ProviderProfile? {
        (await load()).first
    }

    public func saveCredential(_ profile: ProviderProfile, key: String) async throws {
        try await KeychainStore.shared.saveString(key, ref: profile.keychainCredentialRef)
    }
}
