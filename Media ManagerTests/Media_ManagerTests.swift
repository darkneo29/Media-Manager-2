//
//  Media_ManagerTests.swift
//  Media ManagerTests
//
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Media_Manager

private struct TestDefaultsStore {
    let suiteName: String
    let defaults: UserDefaults
}

private final class TestCloudStore: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

struct Media_ManagerTests {

    @Test
    func credentialMigrationMovesSecretsIntoKeychainAndClearsLegacyStores() throws {
        let defaultsStore = makeDefaults(suffix: "migration")
        let cloudStore = TestCloudStore()
        let credentialStore = CredentialStore(serviceName: "tests.credentials.migration.\(UUID().uuidString)")

        defer {
            credentialStore.removeAll()
            clearDefaults(defaultsStore)
        }

        defaultsStore.defaults.set("radarr-secret", forKey: "radarrAPIKey")
        defaultsStore.defaults.set("tmdb-secret", forKey: "tmdbAccessToken")
        cloudStore.set("sonarr-secret", forKey: "sonarrAPIKey")
        cloudStore.set("unraid-secret", forKey: "unraidAPIKey")

        credentialStore.migrateLegacyCredentialsIfNeeded(defaults: defaultsStore.defaults, cloudStore: cloudStore)

        let snapshot = credentialStore.snapshot()
        #expect(snapshot.radarrAPIKey == "radarr-secret")
        #expect(snapshot.sonarrAPIKey == "sonarr-secret")
        #expect(snapshot.tmdbAccessToken == "tmdb-secret")
        #expect(snapshot.unraidAPIKey == "unraid-secret")
        #expect(defaultsStore.defaults.object(forKey: "radarrAPIKey") == nil)
        #expect(defaultsStore.defaults.object(forKey: "tmdbAccessToken") == nil)
        #expect(cloudStore.object(forKey: "sonarrAPIKey") == nil)
        #expect(cloudStore.object(forKey: "unraidAPIKey") == nil)
        #expect(defaultsStore.defaults.integer(forKey: "credentialStoreMigrationVersion") == 1)
    }

    @Test
    func encryptedBackupRoundTripRestoresSettingsAndSecrets() throws {
        let sourceDefaultsStore = makeDefaults(suffix: "backup-source")
        let sourceCredentials = CredentialStore(serviceName: "tests.credentials.backup.source.\(UUID().uuidString)")
        let sourceService = BackupService(
            defaults: sourceDefaultsStore.defaults,
            credentialStore: sourceCredentials,
            encryptionService: BackupEncryptionService()
        )

        let restoreDefaultsStore = makeDefaults(suffix: "backup-destination")
        let restoreCredentials = CredentialStore(serviceName: "tests.credentials.backup.destination.\(UUID().uuidString)")
        let restoreService = BackupService(
            defaults: restoreDefaultsStore.defaults,
            credentialStore: restoreCredentials,
            encryptionService: BackupEncryptionService()
        )

        defer {
            sourceCredentials.removeAll()
            restoreCredentials.removeAll()
            clearDefaults(sourceDefaultsStore)
            clearDefaults(restoreDefaultsStore)
        }

        sourceDefaultsStore.defaults.set("http://radarr.local", forKey: "radarrURL")
        sourceDefaultsStore.defaults.set("http://sonarr.local", forKey: "sonarrURL")
        sourceDefaultsStore.defaults.set("http://sab.local", forKey: "sabnzbURL")
        sourceDefaultsStore.defaults.set("http://tower.local", forKey: "unraidURL")
        sourceDefaultsStore.defaults.set(false, forKey: "unraidShowMediaStackFirst")
        sourceDefaultsStore.defaults.set("fahrenheit", forKey: "unraidTemperatureUnit")

        try sourceCredentials.set("radarr-key", for: .radarrAPIKey)
        try sourceCredentials.set("sonarr-key", for: .sonarrAPIKey)
        try sourceCredentials.set("sab-key", for: .sabnzbAPIKey)
        try sourceCredentials.set("tmdb-token", for: .tmdbAccessToken)
        try sourceCredentials.set("unraid-key", for: .unraidAPIKey)

        let backup = try sourceService.createBackup(passphrase: "correct horse")
        #expect(backup.requiresPassphrase)

        let data = try sourceService.encodeBackup(backup)
        let decodedBackup = try sourceService.decodeBackup(from: data)

        try restoreService.restoreBackup(decodedBackup, passphrase: "correct horse")

        let restoredSecrets = restoreCredentials.snapshot()
        #expect(restoreDefaultsStore.defaults.string(forKey: "radarrURL") == "http://radarr.local")
        #expect(restoreDefaultsStore.defaults.string(forKey: "sonarrURL") == "http://sonarr.local")
        #expect(restoreDefaultsStore.defaults.string(forKey: "sabnzbURL") == "http://sab.local")
        #expect(restoreDefaultsStore.defaults.string(forKey: "unraidURL") == "http://tower.local")
        #expect(restoreDefaultsStore.defaults.bool(forKey: "unraidShowMediaStackFirst") == false)
        #expect(restoreDefaultsStore.defaults.string(forKey: "unraidTemperatureUnit") == "fahrenheit")
        #expect(restoredSecrets.radarrAPIKey == "radarr-key")
        #expect(restoredSecrets.sonarrAPIKey == "sonarr-key")
        #expect(restoredSecrets.sabnzbAPIKey == "sab-key")
        #expect(restoredSecrets.tmdbAccessToken == "tmdb-token")
        #expect(restoredSecrets.unraidAPIKey == "unraid-key")
    }

    @Test
    func encryptedBackupRejectsWrongPassphraseWithoutApplyingChanges() throws {
        let sourceDefaultsStore = makeDefaults(suffix: "wrong-passphrase-source")
        let sourceCredentials = CredentialStore(serviceName: "tests.credentials.wrong-passphrase.source.\(UUID().uuidString)")
        let sourceService = BackupService(
            defaults: sourceDefaultsStore.defaults,
            credentialStore: sourceCredentials,
            encryptionService: BackupEncryptionService()
        )

        let restoreDefaultsStore = makeDefaults(suffix: "wrong-passphrase-destination")
        let restoreCredentials = CredentialStore(serviceName: "tests.credentials.wrong-passphrase.destination.\(UUID().uuidString)")
        let restoreService = BackupService(
            defaults: restoreDefaultsStore.defaults,
            credentialStore: restoreCredentials,
            encryptionService: BackupEncryptionService()
        )

        defer {
            sourceCredentials.removeAll()
            restoreCredentials.removeAll()
            clearDefaults(sourceDefaultsStore)
            clearDefaults(restoreDefaultsStore)
        }

        sourceDefaultsStore.defaults.set("http://radarr.local", forKey: "radarrURL")
        try sourceCredentials.set("radarr-key", for: .radarrAPIKey)
        let backup = try sourceService.createBackup(passphrase: "correct horse")

        restoreDefaultsStore.defaults.set("http://existing.local", forKey: "radarrURL")
        try restoreCredentials.set("existing-key", for: .radarrAPIKey)

        do {
            try restoreService.restoreBackup(backup, passphrase: "wrong battery")
            Issue.record("Expected wrong passphrase restore to throw")
        } catch let error as BackupError {
            switch error {
            case .invalidPassphrase:
                break
            default:
                Issue.record("Unexpected backup error: \(error.localizedDescription)")
            }
        }

        #expect(restoreDefaultsStore.defaults.string(forKey: "radarrURL") == "http://existing.local")
        #expect(restoreCredentials.snapshot().radarrAPIKey == "existing-key")
    }

    @Test
    func legacyPlaintextBackupImportsSecretsIntoKeychain() throws {
        let restoreDefaultsStore = makeDefaults(suffix: "legacy-import")
        let restoreCredentials = CredentialStore(serviceName: "tests.credentials.legacy-import.\(UUID().uuidString)")
        let restoreService = BackupService(
            defaults: restoreDefaultsStore.defaults,
            credentialStore: restoreCredentials,
            encryptionService: BackupEncryptionService()
        )

        defer {
            restoreCredentials.removeAll()
            clearDefaults(restoreDefaultsStore)
        }

        let backup = SettingsBackup(
            radarrURL: "http://radarr.local",
            sonarrURL: "http://sonarr.local",
            sabnzbURL: "http://sab.local",
            tmdbAccessToken: "tmdb-token",
            unraidURL: "http://tower.local",
            unraidShowMediaStackFirst: true,
            unraidTemperatureUnit: "celsius",
            radarrAPIKey: "radarr-key",
            sonarrAPIKey: "sonarr-key",
            sabnzbAPIKey: "sab-key",
            unraidAPIKey: "unraid-key",
            encryptedSecrets: nil
        )

        try restoreService.restoreBackup(backup)

        let restoredSecrets = restoreCredentials.snapshot()
        #expect(restoreDefaultsStore.defaults.string(forKey: "radarrURL") == "http://radarr.local")
        #expect(restoredSecrets.radarrAPIKey == "radarr-key")
        #expect(restoredSecrets.sonarrAPIKey == "sonarr-key")
        #expect(restoredSecrets.sabnzbAPIKey == "sab-key")
        #expect(restoredSecrets.tmdbAccessToken == "tmdb-token")
        #expect(restoredSecrets.unraidAPIKey == "unraid-key")
    }

    @Test
    func cachedImageLoadStateClearsOnURLChangeAndIgnoresStaleResponses() {
        var loadState = CachedAsyncImageLoadState()
        let initialImage = UIImage()
        let freshImage = UIImage()

        loadState.image = initialImage
        let firstRequestID = loadState.beginRequest(for: URL(string: "https://example.com/a.jpg"))
        #expect(loadState.image == nil)
        #expect(loadState.isLoading)

        let secondRequestID = loadState.beginRequest(for: URL(string: "https://example.com/b.jpg"))
        loadState.completeRequest(UIImage(), requestID: firstRequestID)
        #expect(loadState.image == nil)
        #expect(loadState.isLoading)

        loadState.completeRequest(freshImage, requestID: secondRequestID)
        #expect(loadState.image != nil)
        #expect(ObjectIdentifier(loadState.image!) == ObjectIdentifier(freshImage))
        #expect(!loadState.isLoading)
    }

    @Test
    func cachedImageLoadStateClearsImmediatelyForNilURL() {
        var loadState = CachedAsyncImageLoadState()
        loadState.image = UIImage()

        _ = loadState.beginRequest(for: nil)

        #expect(loadState.image == nil)
        #expect(!loadState.isLoading)
    }

    @Test
    func downloadsPollingPolicyOnlyPollsForActiveForegroundConfiguredDownloadsTab() {
        #expect(DownloadsPollingPolicy.shouldPoll(isActiveTab: true, scenePhase: .active, isSabConfigured: true))
        #expect(!DownloadsPollingPolicy.shouldPoll(isActiveTab: false, scenePhase: .active, isSabConfigured: true))
        #expect(!DownloadsPollingPolicy.shouldPoll(isActiveTab: true, scenePhase: .background, isSabConfigured: true))
        #expect(!DownloadsPollingPolicy.shouldPoll(isActiveTab: true, scenePhase: .inactive, isSabConfigured: true))
        #expect(!DownloadsPollingPolicy.shouldPoll(isActiveTab: true, scenePhase: .active, isSabConfigured: false))
    }

    @Test
    func sabQueueResponseDecodesFlexibleActiveDownloadPayloads() throws {
        let payload = """
        {
          "queue": {
            "paused": "false",
            "paused_all": 1,
            "speedlimit": "0",
            "speed": "12.4 M",
            "kbpersec": 2048,
            "slots": [
              {
                "nzo_id": "SABnzbd_nzo_abc",
                "filename": "Movie.Release.2160p",
                "cat": "movies",
                "status": "Downloading",
                "percentage": "52%",
                "mb": 1024.5,
                "mbleft": "491.4",
                "timeleft": "00:05:10"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SabNZBQueueResponse.self, from: payload)

        #expect(!response.queue.paused)
        #expect(response.queue.pausedAll)
        #expect(response.queue.kbpersec == "2048")
        #expect(response.queue.slots.first?.nzo_id == "SABnzbd_nzo_abc")
        #expect(response.queue.slots.first?.percentage == "52%")
    }

    @Test
    func sabHistoryResponseDecodesHistoryItemsAndExpandedStatuses() throws {
        let payload = """
        {
          "history": {
            "slots": [
              {
                "nzo_id": "SABnzbd_nzo_done",
                "name": "Show.Release.S01E01",
                "category": "tv",
                "status": "QuickCheck",
                "size": "1.5 GB",
                "completed": "1782687000",
                "download_time": "360",
                "fail_message": null
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SabNZBHistoryResponse.self, from: payload)
        let item = try #require(response.history.slots.first)

        #expect(item.name == "Show.Release.S01E01")
        #expect(item.category == "tv")
        #expect(item.bytes == 1_610_612_736)
        #expect(item.completed == 1_782_687_000)
        #expect(item.download_time == 360)
        #expect(DownloadStatus(from: item.status) == .quickCheck)
    }

    private func makeDefaults(suffix: String) -> TestDefaultsStore {
        let suiteName = "MediaManagerTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TestDefaultsStore(suiteName: suiteName, defaults: defaults)
    }

    private func clearDefaults(_ store: TestDefaultsStore) {
        store.defaults.removePersistentDomain(forName: store.suiteName)
    }
}
