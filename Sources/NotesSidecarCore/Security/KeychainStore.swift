import Foundation
import Security

protocol KeychainBackend: Sendable {
    func save(_ data: Data, ref: String) throws
    func read(ref: String) throws -> Data?
    func delete(ref: String) throws
}

struct SystemKeychainBackend: KeychainBackend {
    private let service = "com.youwin.NotesSidecar.providers"

    func save(_ data: Data, ref: String) throws {
        // Remove legacy entries that were keyed by account only, then create the
        // stable service/account tuple used by all current builds.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ref
        ] as CFDictionary)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ref,
            kSecAttrService as String: service,
            kSecAttrLabel as String: "Notes Sidecar Provider Credential",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStore.KeychainError.unhandled(status) }
    }

    func read(ref: String) throws -> Data? {
        let currentQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ref,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(currentQuery as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound:
            // One-time migration from builds that omitted kSecAttrService.
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: ref,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var legacyItem: CFTypeRef?
            let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyItem)
            if legacyStatus == errSecSuccess, let data = legacyItem as? Data {
                try save(data, ref: ref)
                return data
            }
            if legacyStatus == errSecItemNotFound { return nil }
            throw KeychainStore.KeychainError.unhandled(legacyStatus)
        default: throw KeychainStore.KeychainError.unhandled(status)
        }
    }

    func delete(ref: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ref
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStore.KeychainError.unhandled(status)
        }
    }
}

public actor KeychainStore {
    public static let shared = KeychainStore(backend: SystemKeychainBackend())
    private let backend: any KeychainBackend
    private enum CacheEntry { case value(Data), missing }
    private var cache: [String: CacheEntry] = [:]

    init(backend: any KeychainBackend) {
        self.backend = backend
    }

    public func saveString(_ value: String, ref: String) throws {
        let data = Data(value.utf8)
        try save(data, ref: ref)
    }

    public func save(_ data: Data, ref: String) throws {
        try backend.save(data, ref: ref)
        cache[ref] = .value(data)
    }

    public func read(ref: String) throws -> Data? {
        if let cached = cache[ref] {
            switch cached {
            case .value(let data): return data
            case .missing: return nil
            }
        }
        let data = try backend.read(ref: ref)
        cache[ref] = data.map(CacheEntry.value) ?? .missing
        return data
    }

    public func readString(ref: String) throws -> String? {
        guard let data = try read(ref: ref) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(ref: String) throws {
        try backend.delete(ref: ref)
        cache.removeValue(forKey: ref)
    }

    public static func maskedTail(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "—" }
        let tail = trimmed.suffix(4)
        return "…\(tail)"
    }

    public enum KeychainError: Error { case unhandled(OSStatus) }
}
