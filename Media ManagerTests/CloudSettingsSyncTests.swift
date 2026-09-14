import CloudKit
import Foundation
import Testing
@testable import Media_Manager

@MainActor
private final class MemorySettings: SettingsSyncLocalStore {
    var values: [String: [String: String]]
    init(_ values: [String: [String: String]] = ["radarr": ["url": "", "credential": ""]]) { self.values = values }
    func read() throws -> [String: [String: String]] { values }
    func apply(_ entries: [String: CloudSettingsEntry]) throws {
        for (key, entry) in entries { values[key] = entry.values }
    }
}

@MainActor
private final class MemoryCloud: SettingsCloudTransport {
    var payload: CloudSettingsPayload?
    var account = "test-account"
    var failure: Error?
    var onFetch: (() -> Void)?
    var conflict: CloudSettingsPayload?
    var saves = 0
    var encryptedFields: [String] = []
    func accountIdentifier() async throws -> String { account }
    func fetch() async throws -> CKRecord? {
        if let failure { throw failure }
        let action = onFetch; onFetch = nil; action?()
        guard let payload else { return nil }
        return try record(payload)
    }
    func record(_ payload: CloudSettingsPayload) throws -> CKRecord {
        let record = CKRecord(recordType: PrivateCloudSettingsTransport.recordType, recordID: PrivateCloudSettingsTransport.recordID)
        record.encryptedValues[PrivateCloudSettingsTransport.encryptedField] = try JSONEncoder().encode(payload) as NSData
        return record
    }
    func save(_ record: CKRecord) async throws -> CKRecord {
        if let conflict { self.conflict = nil; payload = conflict; throw CKError(.serverRecordChanged) }
        saves += 1
        encryptedFields = record.encryptedValues.allKeys()
        payload = try iCloudSyncService.decode(record)
        return record
    }
}

@MainActor
struct CloudSettingsSyncTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CloudSyncTests.\(UUID().uuidString)")! }
    private func entry(_ url: String, _ credential: String, time: Double = 100) -> CloudSettingsEntry {
        CloudSettingsEntry(values: ["url": url, "credential": credential], modifiedAt: time, revision: "test")
    }
    private func service(_ cloud: MemoryCloud, _ local: MemorySettings, _ defaults: UserDefaults) -> iCloudSyncService {
        iCloudSyncService(cloud: cloud, local: local, defaults: defaults, notifications: NotificationCenter(), now: { Date(timeIntervalSince1970: 200) })
    }

    @Test func emptyTVReceivesServerAndKeyTogether() async {
        let cloud = MemoryCloud(), local = MemorySettings(), preferences = defaults()
        cloud.payload = CloudSettingsPayload(entries: ["radarr": entry("https://example.test", "synthetic-key")])
        let sync = service(cloud, local, preferences)
        await sync.enableSync()
        #expect(local.values["radarr"] == cloud.payload?.entries["radarr"]?.values)
        #expect(cloud.saves == 0)
        #expect(sync.lastSyncDate != nil)
    }

    @Test func publishingUsesEncryptedFieldAndNoPlaintextDefaults() async {
        let cloud = MemoryCloud(), local = MemorySettings(["radarr": ["url": "https://example.test", "credential": "synthetic-secret-unique"]]), preferences = defaults()
        let sync = service(cloud, local, preferences)
        await sync.enableSync()
        #expect(cloud.payload?.entries["radarr"]?.values["credential"] == "synthetic-secret-unique")
        #expect(cloud.encryptedFields == [PrivateCloudSettingsTransport.encryptedField])
        let metadata = preferences.data(forKey: "privateCloudSettingsRevisionsV1")!
        #expect(!String(decoding: metadata, as: UTF8.self).contains("synthetic-secret-unique"))
    }

    @Test func failureKeepsSettingsAndDoesNotReportSuccess() async {
        let cloud = MemoryCloud(), local = MemorySettings(), preferences = defaults()
        cloud.failure = CKError(.networkUnavailable)
        let original = local.values
        let sync = service(cloud, local, preferences)
        await sync.enableSync()
        #expect(local.values == original)
        #expect(sync.lastSyncDate == nil)
        if case .error = sync.syncStatus {} else { Issue.record("Expected error") }
    }

    @Test func credentialOnlyEditsAndDeletionPropagate() async {
        let cloud = MemoryCloud(), local = MemorySettings(["radarr": ["url": "https://example.test", "credential": "first"]]), preferences = defaults()
        let sync = service(cloud, local, preferences)
        await sync.enableSync()
        local.values["radarr"]?["credential"] = "second"
        await sync.synchronize()
        #expect(cloud.payload?.entries["radarr"]?.values["credential"] == "second")
        local.values["radarr"] = ["url": "", "credential": ""]
        await sync.synchronize()
        let other = MemorySettings(["radarr": ["url": "https://old.test", "credential": "old"]])
        await service(cloud, other, defaults()).enableSync()
        #expect(other.values["radarr"] == ["url": "", "credential": ""])
    }

    @Test func editDuringFetchSurvives() async {
        let cloud = MemoryCloud(), local = MemorySettings(), preferences = defaults()
        cloud.payload = CloudSettingsPayload(entries: ["radarr": entry("https://remote.test", "remote")])
        cloud.onFetch = { local.values["radarr"] = ["url": "https://edited.test", "credential": "edited"] }
        await service(cloud, local, preferences).enableSync()
        #expect(local.values["radarr"]?["credential"] == "edited")
        #expect(cloud.payload?.entries["radarr"]?.values["credential"] == "edited")
    }

    @Test func conflictRefetchPreservesOtherServer() async {
        let cloud = MemoryCloud(), local = MemorySettings(["radarr": ["url": "https://local.test", "credential": "local"]])
        cloud.conflict = CloudSettingsPayload(entries: ["sonarr": entry("https://other.test", "other")])
        await service(cloud, local, defaults()).enableSync()
        #expect(cloud.payload?.entries["sonarr"]?.values["credential"] == "other")
        #expect(cloud.payload?.entries["radarr"]?.values["credential"] == "local")
    }

    @Test func disableDuringFetchDoesNotApply() async {
        let cloud = MemoryCloud(), local = MemorySettings()
        let sync = service(cloud, local, defaults())
        cloud.payload = CloudSettingsPayload(entries: ["radarr": entry("https://remote.test", "remote")])
        cloud.onFetch = { sync.disableSync() }
        await sync.enableSync()
        #expect(sync.syncStatus == .disabled)
        #expect(local.values["radarr"]?["credential"] == "")
        #expect(cloud.saves == 0)
    }

    @Test func newerFormatAndChangedAccountDoNotOverwrite() async {
        let cloud = MemoryCloud(), local = MemorySettings()
        let sync = service(cloud, local, defaults())
        cloud.payload = CloudSettingsPayload(version: 2, entries: ["radarr": entry("https://remote.test", "remote")])
        await sync.enableSync()
        #expect(local.values["radarr"]?["credential"] == "")
        #expect(cloud.saves == 0)
        cloud.account = "another-account"
        await sync.synchronize()
        #expect(!sync.isEnabled)
        #expect(cloud.saves == 0)
    }

    @Test func firstUpgradePrefersConfiguredPhoneOverStaleURLOnlyTV() async {
        let cloud = MemoryCloud(), local = MemorySettings(["radarr": ["url": "https://current.test", "credential": "current"]])
        cloud.payload = CloudSettingsPayload(entries: ["radarr": entry("https://old.test", "", time: 0)])
        await service(cloud, local, defaults()).enableSync()
        #expect(local.values["radarr"]?["url"] == "https://current.test")
        #expect(cloud.payload?.entries["radarr"]?.values["credential"] == "current")
    }

    @Test func incompleteServerRecordCannotMixWithLocalKey() async {
        let cloud = MemoryCloud(), local = MemorySettings(["radarr": ["url": "https://original.test", "credential": "original"]])
        cloud.payload = CloudSettingsPayload(entries: ["radarr": CloudSettingsEntry(values: ["url": "https://other.test"], modifiedAt: 300, revision: "bad")])
        let sync = service(cloud, local, defaults())
        await sync.enableSync()
        #expect(local.values["radarr"]?["url"] == "https://original.test")
        #expect(cloud.saves == 0)
        #expect(sync.lastSyncDate == nil)
    }

    @Test func deviceStoreWritesKeysToKeychain() throws {
        let preferences = defaults()
        let credentials = CredentialStore(serviceName: "CloudSyncTests.\(UUID().uuidString)")
        defer { credentials.removeAll() }
        let local = DeviceSettingsSyncStore(defaults: preferences, credentials: credentials, refresh: {})
        try local.apply(["radarr": entry("https://example.test", "synthetic-key")])
        #expect(try local.read()["radarr"]?["credential"] == "synthetic-key")
        #expect(preferences.string(forKey: "radarrURL") == "https://example.test")
        #expect(preferences.object(forKey: "radarrAPIKey") == nil)
    }
}
