import CloudKit
import Foundation

/// Success means the private iCloud record was read/saved successfully, not that
/// every other device has already fetched it.
enum iCloudSyncStatus: Equatable {
    case disabled, syncing
    case synced(Date)
    case error(String)

    var displayText: String {
        switch self {
        case .disabled: return "Disabled"
        case .syncing: return "Syncing securely with iCloud…"
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "iCloud updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .error(let message): return message
        }
    }
}

@MainActor
@Observable
final class iCloudSyncService {
    static let shared = iCloudSyncService()
    private(set) var isEnabled: Bool
    private(set) var syncStatus: iCloudSyncStatus = .disabled
    private(set) var lastSyncDate: Date?

    private let cloud: SettingsCloudTransport
    private let local: SettingsSyncLocalStore
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    private var scheduledSync: Task<Void, Never>?
    private var revisions: [String: SettingsSyncRevision]
    private var generation = 0
    private var isApplying = false
    private var needsAnotherSync = false
    private var isRunning = false
    private static let revisionKey = "privateCloudSettingsRevisionsV1"
    private static let accountKey = "privateCloudSettingsAccountV1"

    init(cloud: SettingsCloudTransport? = nil,
         local: SettingsSyncLocalStore? = nil,
         defaults: UserDefaults = .standard, notifications: NotificationCenter = .default,
         now: @escaping () -> Date = Date.init) {
        self.cloud = cloud ?? PrivateCloudSettingsTransport()
        self.local = local ?? DeviceSettingsSyncStore()
        self.defaults = defaults
        self.notifications = notifications
        self.now = now
        isEnabled = defaults.bool(forKey: "iCloudSyncEnabled")
        revisions = defaults.data(forKey: Self.revisionKey).flatMap { try? JSONDecoder().decode([String: SettingsSyncRevision].self, from: $0) } ?? [:]
        // Register before any cloud request. Keychain-only edits also trigger sync.
        for name in [UserDefaults.didChangeNotification, CredentialStore.didChangeNotification] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleLocalSync() }
            })
        }
        observers.append(notifications.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.disableSync()
                self.defaults.removeObject(forKey: Self.accountKey)
                self.revisions = [:]
                self.defaults.removeObject(forKey: Self.revisionKey)
                self.syncStatus = .error(SettingsSyncError.accountChanged.localizedDescription)
            }
        })
    }

    func enableSync() async {
        guard !isEnabled else { return }
        isEnabled = true
        defaults.set(true, forKey: "iCloudSyncEnabled")
        await synchronize()
    }

    func disableSync() {
        isEnabled = false
        generation += 1
        scheduledSync?.cancel()
        scheduledSync = nil
        defaults.set(false, forKey: "iCloudSyncEnabled")
        syncStatus = .disabled
    }

    func syncNow() {
        guard !isRunning else { needsAnotherSync = true; return }
        scheduledSync?.cancel()
        scheduledSync = Task { await synchronize() }
    }

    private func scheduleLocalSync() {
        guard isEnabled, !isApplying else { return }
        do {
            let changed = try local.read().contains { key, value in
                try SettingsSyncRevision.fingerprint(value) != revisions[key]?.fingerprint
            }
            guard changed else { return }
        } catch { return }
        if isRunning { needsAnotherSync = true; return }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await self?.synchronize()
        }
    }

    /// Single-flight, read-before-write sync. Tests inject an isolated transport
    /// and local store; the production transport always uses the private database.
    func synchronize() async {
        guard isEnabled else { return }
        guard !isRunning else { needsAnotherSync = true; return }
        isRunning = true
        let operationGeneration = generation
        defer {
            isRunning = false
            if isEnabled, generation != operationGeneration, needsAnotherSync {
                scheduledSync = Task { [weak self] in await self?.synchronize() }
            }
        }
        syncStatus = .syncing
        do {
            repeat {
                needsAnotherSync = false
                try await synchronizeOnce(generation: operationGeneration)
            } while needsAnotherSync && isEnabled && generation == operationGeneration && !Task.isCancelled
            guard isEnabled, generation == operationGeneration, !Task.isCancelled else { return }
            let date = now()
            lastSyncDate = date
            syncStatus = .synced(date)
        } catch {
            guard isEnabled, generation == operationGeneration else { return }
            if error is CancellationError {
                syncStatus = .error("Sync interrupted. Try Sync Now again.")
            } else if let ck = error as? CKError {
                switch ck.code {
                case .notAuthenticated: syncStatus = .error("Sign in to iCloud in this device’s Settings, then try Sync Now.")
                case .networkUnavailable, .networkFailure: syncStatus = .error("iCloud is unavailable. Check your connection and try again.")
                case .quotaExceeded: syncStatus = .error("Your iCloud storage is full.")
                case .serverRejectedRequest, .invalidArguments: syncStatus = .error("iCloud sync needs a server configuration update. Local settings were kept.")
                default: syncStatus = .error("iCloud could not complete sync. Try again shortly.")
                }
            } else { syncStatus = .error(error.localizedDescription) }
        }
    }

    private func checkpoint(_ expected: Int) throws {
        try Task.checkCancellation()
        guard isEnabled, expected == generation else { throw CancellationError() }
    }

    private func synchronizeOnce(generation expected: Int) async throws {
        let account = try await cloud.accountIdentifier()
        try checkpoint(expected)
        if let previous = defaults.string(forKey: Self.accountKey), previous != account {
            disableSync()
            defaults.set(account, forKey: Self.accountKey)
            revisions = [:]
            defaults.removeObject(forKey: Self.revisionKey)
            syncStatus = .error(SettingsSyncError.accountChanged.localizedDescription)
            throw SettingsSyncError.accountChanged
        }
        defaults.set(account, forKey: Self.accountKey)
        let localValues = try local.read()
        let pending = try payload(for: localValues)
        for attempt in 0..<3 {
            let fetched = try await cloud.fetch()
            try checkpoint(expected)
            let remote = try Self.decode(fetched)
            let merged = remote.merging(pending)
            let record = fetched ?? CKRecord(recordType: PrivateCloudSettingsTransport.recordType, recordID: PrivateCloudSettingsTransport.recordID)
            if merged != remote {
                record.encryptedValues[PrivateCloudSettingsTransport.encryptedField] = try JSONEncoder().encode(merged) as NSData
                do { _ = try await cloud.save(record) }
                catch let error as CKError where error.code == .serverRecordChanged {
                    if attempt == 2 { throw SettingsSyncError.conflict }
                    continue
                }
            }
            try checkpoint(expected)
            // A local edit made during the network round-trip must survive.
            guard try local.read() == localValues else { needsAnotherSync = true; return }
            isApplying = true
            defer { isApplying = false }
            try local.apply(merged.entries)
            let applied = try local.read()
            for (key, entry) in merged.entries {
                guard let values = applied[key] else { continue }
                revisions[key] = SettingsSyncRevision(fingerprint: try SettingsSyncRevision.fingerprint(values), modifiedAt: entry.modifiedAt, revision: entry.revision)
            }
            try persistRevisions()
            return
        }
    }

    private func payload(for values: [String: [String: String]]) throws -> CloudSettingsPayload {
        var result = CloudSettingsPayload()
        for (key, value) in values {
            let fingerprint = try SettingsSyncRevision.fingerprint(value)
            let previous = revisions[key]
            // Unconfigured devices do not publish empty server/credential records.
            var revision = previous ?? SettingsSyncRevision(fingerprint: fingerprint, modifiedAt: 0, revision: "migration")
            if previous != nil && revision.fingerprint != fingerprint {
                revision = SettingsSyncRevision(fingerprint: fingerprint, modifiedAt: max(now().timeIntervalSince1970, revision.modifiedAt + 0.001), revision: UUID().uuidString)
            }
            revisions[key] = revision
            if revision.modifiedAt == 0 && value.values.allSatisfy({ $0.isEmpty }) { continue }
            result.entries[key] = CloudSettingsEntry(values: value, modifiedAt: revision.modifiedAt, revision: revision.revision)
        }
        try persistRevisions()
        return result
    }

    private func persistRevisions() throws {
        defaults.set(try JSONEncoder().encode(revisions), forKey: Self.revisionKey)
    }

    static func decode(_ record: CKRecord?) throws -> CloudSettingsPayload {
        guard let record else { return CloudSettingsPayload() }
        guard let data = record.encryptedValues[PrivateCloudSettingsTransport.encryptedField] as? Data else {
            throw SettingsSyncError.invalidResponse
        }
        let payload = try JSONDecoder().decode(CloudSettingsPayload.self, from: data)
        guard payload.version == 1 else { throw SettingsSyncError.newerVersion }
        for (key, entry) in payload.entries {
            guard entry.modifiedAt.isFinite, entry.modifiedAt >= 0, !entry.revision.isEmpty else {
                throw SettingsSyncError.invalidResponse
            }
            if ["radarr", "sonarr", "sabnzb", "unraid"].contains(key) {
                guard entry.values["url"] != nil, entry.values["credential"] != nil else {
                    throw SettingsSyncError.invalidResponse
                }
            }
        }
        return payload
    }
}
