//
//  iCloudSyncService.swift
//  Media Manager
//
//  Handles iCloud Key-Value sync for settings synchronization across devices.
//

import Foundation

/// Sync status for UI display
enum iCloudSyncStatus: Equatable {
    case disabled
    case syncing
    case synced(Date)
    case error(String)

    var displayText: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .syncing:
            return "Syncing..."
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// Service for syncing settings via iCloud Key-Value Store
@MainActor
@Observable
final class iCloudSyncService {
    static let shared = iCloudSyncService()

    // MARK: - Observable State

    /// Current sync status for UI binding
    private(set) var syncStatus: iCloudSyncStatus = .disabled

    /// Last successful sync timestamp
    private(set) var lastSyncDate: Date?

    // MARK: - Private Properties

    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let localDefaults = UserDefaults.standard

    /// Flag to prevent sync loops when we're updating from cloud
    private var isUpdatingFromCloud = false

    /// Flag to prevent sync loops during push operations
    private var isPushingToCloud = false

    /// Keys that should be synced
    private let syncableKeys: [String] = [
        "radarrURL",
        "sonarrURL",
        "sabnzbURL",
        "unraidURL",
        "unraidShowMediaStackFirst",
        "unraidTemperatureUnit"
    ]
    private let secretKeys = CredentialStore.CredentialKey.allCases.map(\.rawValue)

    /// Local-only keys (not synced)
    private enum LocalKeys {
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let lastLocalChangeTimestamp = "lastLocalChangeTimestamp"
        static let initialMigrationComplete = "iCloudInitialMigrationComplete"
    }

    /// iCloud keys
    private enum CloudKeys {
        static let syncTimestamp = "iCloudSyncTimestamp"
        static let settingsVersion = "iCloudSettingsVersion"
    }

    /// Whether iCloud sync is enabled (stored locally, not synced)
    private(set) var isEnabled: Bool = false

    private struct SyncSnapshot {
        let localTimestamp: TimeInterval
        let cloudTimestamp: TimeInterval
        let localValueCount: Int
        let cloudValueCount: Int

        var localHasData: Bool { localValueCount > 0 }
        var cloudHasData: Bool { cloudValueCount > 0 }
    }

    private enum SyncResolution {
        case pullCloudToLocal
        case pushLocalToCloud
        case noData
    }

    // MARK: - Initialization

    private init() {
        // Load initial state from UserDefaults
        isEnabled = localDefaults.bool(forKey: LocalKeys.iCloudSyncEnabled)

        if isEnabled {
            let timestamp = ubiquitousStore.double(forKey: CloudKeys.syncTimestamp)
            if timestamp > 0 {
                let syncDate = Date(timeIntervalSince1970: timestamp)
                lastSyncDate = syncDate
                syncStatus = .synced(syncDate)
            }
            purgeCloudSecrets()
            startSync()
        }
    }

    // MARK: - Public Methods

    /// Enable sync and perform initial migration
    func enableSync() async {
        guard !isEnabled else { return }

        // Update stored property immediately for UI
        isEnabled = true
        syncStatus = .syncing
        localDefaults.set(true, forKey: LocalKeys.iCloudSyncEnabled)

        purgeCloudSecrets()
        ubiquitousStore.synchronize()

        // Perform initial migration BEFORE registering for notifications
        await performInitialMigration()

        // Force sync to iCloud
        purgeCloudSecrets()
        ubiquitousStore.synchronize()

        // Now register for ongoing notifications
        startSync()

        updateSyncStatus()
    }

    /// Disable sync (keeps local data, stops syncing)
    func disableSync() {
        isEnabled = false
        localDefaults.set(false, forKey: LocalKeys.iCloudSyncEnabled)
        stopSync()
        syncStatus = .disabled
    }

    /// Force a sync now
    func syncNow() {
        guard isEnabled else { return }

        syncStatus = .syncing
        purgeCloudSecrets()
        ubiquitousStore.synchronize()
        applyResolvedSync()
        purgeCloudSecrets()
        ubiquitousStore.synchronize()

        updateSyncStatus()
    }

    // MARK: - Initial Migration

    /// Returns true when a stored value should be treated as meaningful sync data.
    private func hasMeaningfulValue(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let stringValue = value as? String {
            return !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func performInitialMigration() async {
        let migrationComplete = localDefaults.bool(forKey: LocalKeys.initialMigrationComplete)
        let snapshot = makeSyncSnapshot()

        #if DEBUG
        print("[iCloudSync] Migration - Local values: \(snapshot.localValueCount), Cloud values: \(snapshot.cloudValueCount)")
        print("[iCloudSync] Migration - Local timestamp: \(snapshot.localTimestamp), Cloud timestamp: \(snapshot.cloudTimestamp)")
        print("[iCloudSync] Migration - Already complete: \(migrationComplete)")
        #endif

        applyResolvedSync(snapshot: snapshot)
        localDefaults.set(true, forKey: LocalKeys.initialMigrationComplete)
        purgeCloudSecrets()
    }

    private func makeSyncSnapshot() -> SyncSnapshot {
        SyncSnapshot(
            localTimestamp: localDefaults.double(forKey: LocalKeys.lastLocalChangeTimestamp),
            cloudTimestamp: ubiquitousStore.double(forKey: CloudKeys.syncTimestamp),
            localValueCount: meaningfulSyncableValueCount(in: localDefaults),
            cloudValueCount: meaningfulSyncableValueCount(in: ubiquitousStore)
        )
    }

    private func meaningfulSyncableValueCount(in store: KeyValueStoring) -> Int {
        syncableKeys.reduce(into: 0) { count, key in
            if hasMeaningfulValue(store.object(forKey: key)) {
                count += 1
            }
        }
    }

    private func resolution(for snapshot: SyncSnapshot) -> SyncResolution {
        if snapshot.cloudHasData {
            if !snapshot.localHasData {
                return .pullCloudToLocal
            }

            if snapshot.cloudTimestamp > snapshot.localTimestamp {
                return .pullCloudToLocal
            }

            if snapshot.localTimestamp == 0,
               snapshot.cloudValueCount >= snapshot.localValueCount {
                return .pullCloudToLocal
            }
        }

        if snapshot.localHasData {
            if !snapshot.cloudHasData || snapshot.localTimestamp > snapshot.cloudTimestamp {
                return .pushLocalToCloud
            }
        }

        return .noData
    }

    private func applyResolvedSync(snapshot: SyncSnapshot? = nil) {
        let snapshot = snapshot ?? makeSyncSnapshot()

        switch resolution(for: snapshot) {
        case .pullCloudToLocal:
            #if DEBUG
            print("[iCloudSync] Pulling settings from iCloud")
            #endif
            pullCloudToLocal()
        case .pushLocalToCloud:
            #if DEBUG
            print("[iCloudSync] Pushing local settings to iCloud")
            #endif
            pushLocalToCloud()
        case .noData:
            #if DEBUG
            print("[iCloudSync] No settings changes to sync")
            #endif
            break
        }
    }

    // MARK: - Notification Tokens

    private var remoteChangeObserver: Any?
    private var localChangeObserver: Any?

    // MARK: - Sync Operations

    private func startSync() {
        // Register for remote change notifications (closure-based, guaranteed main queue)
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleRemoteChange(notification)
            }
        }

        // Register for local changes (closure-based, guaranteed main queue)
        localChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleLocalChange(notification)
            }
        }

        // Trigger initial sync
        purgeCloudSecrets()
        ubiquitousStore.synchronize()
    }

    private func stopSync() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
        if let observer = localChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            localChangeObserver = nil
        }
    }

    /// Push local UserDefaults values to iCloud
    private func pushLocalToCloud() {
        guard !isPushingToCloud else { return }
        isPushingToCloud = true
        defer { isPushingToCloud = false }

        let timestamp = Date().timeIntervalSince1970

        for key in syncableKeys {
            if let value = localDefaults.object(forKey: key) {
                ubiquitousStore.set(value, forKey: key)
            }
        }

        ubiquitousStore.set(timestamp, forKey: CloudKeys.syncTimestamp)
        ubiquitousStore.set(Int64(3), forKey: CloudKeys.settingsVersion)

        localDefaults.set(timestamp, forKey: LocalKeys.lastLocalChangeTimestamp)
        purgeCloudSecrets()

        #if DEBUG
        print("[iCloudSync] Pushed local settings to iCloud")
        #endif
    }

    /// Pull iCloud values to local UserDefaults
    private func pullCloudToLocal() {
        isUpdatingFromCloud = true

        for key in syncableKeys {
            if let value = ubiquitousStore.object(forKey: key) {
                localDefaults.set(value, forKey: key)
            }
        }
        purgeCloudSecrets()

        // Force UserDefaults sync for @AppStorage
        localDefaults.synchronize()

        // Update local timestamp to match cloud
        let cloudTimestamp = ubiquitousStore.double(forKey: CloudKeys.syncTimestamp)
        localDefaults.set(cloudTimestamp, forKey: LocalKeys.lastLocalChangeTimestamp)

        isUpdatingFromCloud = false

        #if DEBUG
        print("[iCloudSync] Pulled settings from iCloud to local")
        #endif
    }

    // MARK: - Notification Handlers

    private func handleLocalChange(_ notification: Notification) {
        guard isEnabled, !isUpdatingFromCloud, !isPushingToCloud else { return }

        // Push changes to iCloud
        pushLocalToCloud()
        ubiquitousStore.synchronize()
        updateSyncStatus()
    }

    private func handleRemoteChange(_ notification: Notification) {
        guard isEnabled else { return }

        guard let userInfo = notification.userInfo,
              let reasonNumber = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber else {
            return
        }

        let reason = reasonNumber.intValue

        #if DEBUG
        print("[iCloudSync] Remote change received, reason: \(reason)")
        #endif

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // New data from iCloud
            purgeCloudSecrets()
            handleIncomingSync(userInfo: userInfo)

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            syncStatus = .error("iCloud storage quota exceeded")

        case NSUbiquitousKeyValueStoreAccountChange:
            // iCloud account changed - reset migration flag
            localDefaults.set(false, forKey: LocalKeys.initialMigrationComplete)
            Task { @MainActor in
                await performInitialMigration()
            }

        default:
            break
        }
    }

    private func handleIncomingSync(userInfo: [AnyHashable: Any]) {
        // Get changed keys
        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        // Check if any of our syncable keys changed
        let relevantChanges = changedKeys.filter { syncableKeys.contains($0) || $0 == CloudKeys.syncTimestamp }

        guard !relevantChanges.isEmpty else { return }

        #if DEBUG
        print("[iCloudSync] Relevant changed keys: \(relevantChanges)")
        #endif

        // Compare timestamps for conflict resolution
        let localTimestamp = localDefaults.double(forKey: LocalKeys.lastLocalChangeTimestamp)
        let cloudTimestamp = ubiquitousStore.double(forKey: CloudKeys.syncTimestamp)

        if cloudTimestamp > localTimestamp {
            // Cloud is newer - pull changes
            pullCloudToLocal()
        }
        // Otherwise, local changes are newer - they'll be pushed on next local change

        updateSyncStatus()
    }

    private func updateSyncStatus() {
        let timestamp = ubiquitousStore.double(forKey: CloudKeys.syncTimestamp)
        if timestamp > 0 {
            let syncDate = Date(timeIntervalSince1970: timestamp)
            lastSyncDate = syncDate
            syncStatus = .synced(syncDate)
        } else {
            syncStatus = .synced(Date())
            lastSyncDate = Date()
        }
    }

    private func purgeCloudSecrets() {
        for key in secretKeys {
            ubiquitousStore.removeObject(forKey: key)
        }
    }
}
