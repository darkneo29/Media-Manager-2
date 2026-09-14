import Foundation
import Security

protocol KeyValueStoring: AnyObject {
    nonisolated func object(forKey defaultName: String) -> Any?
    nonisolated func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}
extension NSUbiquitousKeyValueStore: KeyValueStoring {}

struct StoredCredentials: Codable, Equatable {
    var radarrAPIKey: String?
    var sonarrAPIKey: String?
    var sabnzbAPIKey: String?
    var tmdbAccessToken: String?
    var unraidAPIKey: String?

    var hasSecrets: Bool {
        allValues.contains { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }

    var allValues: [String?] {
        [
            radarrAPIKey,
            sonarrAPIKey,
            sabnzbAPIKey,
            tmdbAccessToken,
            unraidAPIKey
        ]
    }
}

final class CredentialStore {
    nonisolated static let didChangeNotification = Notification.Name("MediaManagerCredentialsChanged")

    enum CredentialKey: String, CaseIterable {
        case radarrAPIKey
        case sonarrAPIKey
        case sabnzbAPIKey
        case tmdbAccessToken
        case unraidAPIKey
    }

    nonisolated static let shared = CredentialStore()
    private let migrationVersionKey = "credentialStoreMigrationVersion"
    private let migrationVersion = 1
    private let serviceName: String

    nonisolated init(serviceName: String = Bundle.main.bundleIdentifier ?? "com.myandroidtv.MediaManager.credentials") {
        self.serviceName = serviceName
    }

    nonisolated func string(for key: CredentialKey) -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }

    /// Sync must distinguish a missing key from a locked/unavailable Keychain.
    nonisolated func syncString(for key: CredentialKey) throws -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.keychainFailure(status: status)
        }
        return value
    }

    nonisolated func set(_ value: String, for key: CredentialKey) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychainFailure(status: status)
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            return
        }

        let data = Data(trimmed.utf8)
        var query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw CredentialStoreError.keychainFailure(status: updateStatus)
            }
        } else if status == errSecItemNotFound {
            for (key, value) in attributes {
                query[key] = value
            }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainFailure(status: addStatus)
            }
        } else {
            throw CredentialStoreError.keychainFailure(status: status)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    nonisolated func removeValue(for key: CredentialKey) {
        let query = baseQuery(for: key)
        if SecItemDelete(query as CFDictionary) == errSecSuccess {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    nonisolated func removeAll() {
        CredentialKey.allCases.forEach(removeValue(for:))
    }

    nonisolated func snapshot() -> StoredCredentials {
        StoredCredentials(
            radarrAPIKey: normalizedSecret(string(for: .radarrAPIKey)),
            sonarrAPIKey: normalizedSecret(string(for: .sonarrAPIKey)),
            sabnzbAPIKey: normalizedSecret(string(for: .sabnzbAPIKey)),
            tmdbAccessToken: normalizedSecret(string(for: .tmdbAccessToken)),
            unraidAPIKey: normalizedSecret(string(for: .unraidAPIKey))
        )
    }

    nonisolated func migrateLegacyCredentialsIfNeeded(
        defaults: UserDefaults = .standard,
        cloudStore: KeyValueStoring? = NSUbiquitousKeyValueStore.default
    ) {
        let storedMigrationVersion = defaults.integer(forKey: migrationVersionKey)
        var allMigrationsSucceeded = true

        for key in CredentialKey.allCases {
            let localValue = normalizedSecret(defaults.string(forKey: key.rawValue) ?? "")
            let cloudValue = normalizedSecret(cloudStore?.object(forKey: key.rawValue) as? String ?? "")

            if string(for: key).isEmpty {
                if let migratedValue = localValue ?? cloudValue {
                    do {
                        try set(migratedValue, for: key)
                    } catch {
                        // Keep both legacy sources intact so a transient Keychain
                        // failure cannot destroy the only copy of a credential.
                        allMigrationsSucceeded = false
                        continue
                    }
                }
            }

            if !string(for: key).isEmpty || (localValue == nil && cloudValue == nil) {
                defaults.removeObject(forKey: key.rawValue)
                cloudStore?.removeObject(forKey: key.rawValue)
            } else {
                allMigrationsSucceeded = false
            }
        }

        if let cloudStore = cloudStore as? NSUbiquitousKeyValueStore {
            cloudStore.synchronize()
        }

        if allMigrationsSucceeded, storedMigrationVersion < migrationVersion {
            defaults.set(migrationVersion, forKey: migrationVersionKey)
        }
    }

    private nonisolated func baseQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    private nonisolated func normalizedSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CredentialStoreError: LocalizedError {
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error (\(status))"
        }
    }
}
