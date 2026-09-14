import CloudKit
import CryptoKit
import Foundation

/// A server URL and its credential travel as one value. Empty values are deletion
/// records, not an invitation to resurrect another device's older configuration.
struct CloudSettingsEntry: Codable, Equatable {
    var values: [String: String]
    var modifiedAt: TimeInterval
    var revision: String
}

struct CloudSettingsPayload: Codable, Equatable {
    var version = 1
    var entries: [String: CloudSettingsEntry] = [:]

    func merging(_ local: Self) -> Self {
        var result = self
        for (key, candidate) in local.entries {
            guard let existing = result.entries[key] else {
                result.entries[key] = candidate
                continue
            }
            // On first upgrade, prefer a complete server over a URL-only TV
            // snapshot, including when the TV still has an older address.
            if candidate.modifiedAt == 0, existing.modifiedAt == 0,
               !(candidate.values["url"] ?? "").isEmpty,
               !(candidate.values["credential"] ?? "").isEmpty,
               (existing.values["credential"] ?? "").isEmpty {
                result.entries[key] = candidate
            } else if candidate.modifiedAt == 0, existing.modifiedAt == 0,
               candidate.values["url"] == existing.values["url"] {
                var combined = existing
                for (field, value) in candidate.values where !(value.isEmpty) && (combined.values[field] ?? "").isEmpty {
                    combined.values[field] = value
                }
                result.entries[key] = combined
            } else if candidate.modifiedAt > existing.modifiedAt ||
                        (candidate.modifiedAt == existing.modifiedAt && candidate.modifiedAt > 0 && candidate.revision > existing.revision) {
                result.entries[key] = candidate
            }
        }
        return result
    }
}

@MainActor
protocol SettingsCloudTransport {
    func accountIdentifier() async throws -> String
    func fetch() async throws -> CKRecord?
    func save(_ record: CKRecord) async throws -> CKRecord
}

@MainActor
final class PrivateCloudSettingsTransport: SettingsCloudTransport {
    static let recordType = "MediaManagerSettingsV1"
    static let recordID = CKRecord.ID(recordName: "settings-v1")
    static let encryptedField = "encryptedPayload"
    private let container = CKContainer(identifier: "iCloud.myandroidremote.ssh")

    func accountIdentifier() async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw CKError(.notAuthenticated)
        }
        return try await container.userRecordID().recordName
    }

    func fetch() async throws -> CKRecord? {
        do {
            return try await container.privateCloudDatabase.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(_ record: CKRecord) async throws -> CKRecord {
        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
        )
        guard let saved = result.saveResults[record.recordID] else {
            throw SettingsSyncError.invalidResponse
        }
        return try saved.get()
    }
}

enum SettingsSyncError: LocalizedError {
    case invalidResponse, newerVersion, accountChanged, conflict
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "iCloud returned invalid settings. Local settings were kept."
        case .newerVersion: return "Update the app on this device to sync these settings."
        case .accountChanged: return "Your iCloud account changed. Enable sync again to use the new account."
        case .conflict: return "Settings changed on another device. Try Sync Now again."
        }
    }
}

@MainActor
protocol SettingsSyncLocalStore {
    func read() throws -> [String: [String: String]]
    func apply(_ entries: [String: CloudSettingsEntry]) throws
}

@MainActor
final class DeviceSettingsSyncStore: SettingsSyncLocalStore {
    private let defaults: UserDefaults
    private let credentials: CredentialStore
    private let refresh: @MainActor () -> Void
    private let servers: [(String, CredentialStore.CredentialKey)] = [
        ("radarr", .radarrAPIKey), ("sonarr", .sonarrAPIKey),
        ("sabnzb", .sabnzbAPIKey), ("unraid", .unraidAPIKey)
    ]

    init(defaults: UserDefaults = .standard, credentials: CredentialStore = .shared,
         refresh: @escaping @MainActor () -> Void = { ConfigurationManager.shared.refreshConfiguration(invalidateCaches: true) }) {
        self.defaults = defaults
        self.credentials = credentials
        self.refresh = refresh
    }

    func read() throws -> [String: [String: String]] {
        var values: [String: [String: String]] = [:]
        for (name, key) in servers {
            values[name] = ["url": defaults.string(forKey: name + "URL") ?? "", "credential": try credentials.syncString(for: key)]
        }
        values["tmdb"] = ["credential": try credentials.syncString(for: .tmdbAccessToken)]
        values["unraidPreferences"] = [
            "temperatureUnit": defaults.string(forKey: "unraidTemperatureUnit") ?? "celsius",
            "showMediaStackFirst": String(defaults.object(forKey: "unraidShowMediaStackFirst") as? Bool ?? true)
        ]
        return values
    }

    func apply(_ entries: [String: CloudSettingsEntry]) throws {
        let previous = try read()
        guard entries.contains(where: { previous[$0.key] != $0.value.values }) else { return }
        var changedKeys: [(CredentialStore.CredentialKey, String)] = []
        do {
            for (name, key) in servers + [("tmdb", .tmdbAccessToken)] {
                guard let entry = entries[name], let value = entry.values["credential"], value != previous[name]?["credential"] else { continue }
                try credentials.set(value, for: key)
                changedKeys.append((key, previous[name]?["credential"] ?? ""))
            }
        } catch {
            for (key, value) in changedKeys.reversed() { try? credentials.set(value, for: key) }
            throw error
        }
        // Publish URLs only after all Keychain writes succeed.
        for (name, _) in servers {
            if let value = entries[name]?.values["url"] { defaults.set(value, forKey: name + "URL") }
        }
        if let prefs = entries["unraidPreferences"]?.values {
            if let unit = prefs["temperatureUnit"] { defaults.set(unit, forKey: "unraidTemperatureUnit") }
            if let first = prefs["showMediaStackFirst"] { defaults.set(first == "true", forKey: "unraidShowMediaStackFirst") }
        }
        refresh()
    }
}

/// Only fingerprints and revision metadata are persisted outside the Keychain.
struct SettingsSyncRevision: Codable {
    var fingerprint: String
    var modifiedAt: TimeInterval
    var revision: String

    static func fingerprint(_ values: [String: String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(values)).map { String(format: "%02x", $0) }.joined()
    }
}
