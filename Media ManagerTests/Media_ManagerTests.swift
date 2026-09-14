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
    @Test @MainActor
    func calendarHeadingsMatchDeviceWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        #expect(CalendarWeekdayLabels.ordered(for: calendar) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        calendar.firstWeekday = 2
        #expect(CalendarWeekdayLabels.ordered(for: calendar) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        calendar.firstWeekday = 7
        #expect(CalendarWeekdayLabels.ordered(for: calendar) == ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"])
    }

    @Test @MainActor
    func libraryLinksNeverResolveAnOverlappingExternalID() {
        let wrongMovie = Movie(id: 8, title: "Wrong", year: 2020, overview: nil, runtime: 0, monitored: true, status: "released", images: [], tmdbId: 42)
        let rightMovie = Movie(id: 42, title: "Right", year: 2020, overview: nil, runtime: 0, monitored: true, status: "released", images: [], tmdbId: 100)
        #expect(LibraryDeepLink.resolve(42, in: [wrongMovie, rightMovie])?.title == "Right")
        #expect(LibraryDeepLink.resolve(42, in: [wrongMovie]) == nil)
        #expect(LibraryDeepLink.resolve(0, in: [rightMovie]) == nil)
    }

    @Test @MainActor
    func mediaLinksRejectInvalidLibraryIDsAndExtraPathSegments() {
        let handler = DeepLinkHandler.shared
        defer { handler.clearPendingDestination() }
        for link in ["mediamanager://movie/0", "mediamanager://tvshow/-1", "mediamanager://movie/42/extra", "mediamanager://tvshow/abc"] {
            handler.clearPendingDestination()
            handler.handle(url: URL(string: link)!)
            #expect(handler.pendingDestination == nil)
        }
        handler.handle(url: URL(string: "mediamanager://movie/42")!)
        #expect(handler.pendingDestination == .movie(id: 42))
    }



    @Test @MainActor
    func unconfiguredLibraryClearsStaleDataWithoutRequestErrors() async {
        let library = LibraryStateManager(isRadarrConfigured: { false }, isSonarrConfigured: { false })
        library.addMovieLocally(Movie(id: 1, title: "Old server movie", year: 2020, overview: nil, runtime: 0, monitored: true, status: "released", images: []))
        library.addShowLocally(TVShow(id: 2, title: "Old server show", year: 2020, overview: nil, network: nil, status: "ended", monitored: true, qualityProfileId: 1, images: [], statistics: nil))
        await library.loadAll(forceRefresh: true)
        #expect(library.movies.isEmpty)
        #expect(library.tvShows.isEmpty)
        #expect(library.qualityProfiles.isEmpty)
        #expect(library.moviesErrorMessage == nil)
        #expect(library.showsErrorMessage == nil)
        #expect(library.qualityProfilesErrorMessage == nil)
        #expect(library.lastMoviesRefresh == nil)
        #expect(library.lastShowsRefresh == nil)
        #expect(!library.isLoadingMovies && !library.isLoadingShows && !library.isLoadingProfiles)
    }

    @Test @MainActor
    func malformedDownloadMetricsDoNotCrashQueueOrHistory() throws {
        let queueData = Data(#"{"queue":{"kbpersec":"nan","slots":[{"nzo_id":"1","filename":"Example","percentage":"nan","mb":"1e100","mbleft":"-5"}]}}"#.utf8)
        let response = try JSONDecoder().decode(SabNZBQueueResponse.self, from: queueData)
        let queue = SabNZBService.shared.convertToDownloadQueue(response)
        #expect(queue.speed == 0)
        let download = try #require(queue.downloads.first)
        #expect(download.progress == 0)
        #expect(download.size == 0)

        let historyData = Data(#"{"history":{"slots":[{"name":"Example","bytes":1e100,"completed":1e100,"download_time":1e100,"size":"999999999999999999999999999999 TB"}]}}"#.utf8)
        let history = try JSONDecoder().decode(SabNZBHistoryResponse.self, from: historyData)
        let item = try #require(history.history.slots.first)
        #expect(item.bytes == 0)
        #expect(item.completed == 0)
        #expect(item.download_time == 0)
        #expect(ServerMetric.byteCount(.infinity) == 0)
        #expect(ServerMetric.byteCount(1536.8) == 1536)
    }

    @Test
    func rootFolderEditUpdatesDestinationAndPreservesOtherFields() throws {
        let original: [String: Any] = [
            "path": "/movies/Arrival (2016)", "rootFolderPath": "/movies",
            "qualityProfileId": 7, "monitored": true
        ]
        let moved = try MediaFolderPath.applyingRoot("/archive/", to: original)
        #expect(moved["path"] as? String == "/archive/Arrival (2016)")
        #expect(moved["rootFolderPath"] as? String == "/archive/")
        #expect(moved["qualityProfileId"] as? Int == 7)
        #expect(moved["monitored"] as? Bool == true)
        let unchanged = try MediaFolderPath.applyingRoot("/movies/", to: original)
        #expect(unchanged["path"] as? String == original["path"] as? String)
    }

    @Test
    func rootFolderEditSupportsWindowsAndMissingRootMetadata() throws {
        let original: [String: Any] = ["path": #"C:\TV\Example Show"#]
        #expect(MediaFolderPath.currentRoot(rootFolderPath: nil, path: original["path"] as? String) == #"C:\TV"#)
        let moved = try MediaFolderPath.applyingRoot(#"D:\Shows"#, to: original)
        #expect(moved["path"] as? String == #"D:\Shows\Example Show"#)
        let unix = try MediaFolderPath.applyingRoot("/new", to: ["path": "/old/Example Show"])
        #expect(unix["path"] as? String == "/new/Example Show")
        #expect(MediaFolderPath.currentRoot(rootFolderPath: nil, path: "/Example Show") == "/")
    }

    @Test
    func rootFolderEditPreservesUnknownPathUnlessUserChoosesDestination() throws {
        let unchanged = try MediaFolderPath.applyingRoot(nil, to: ["monitored": false])
        #expect(unchanged["path"] == nil)
        #expect(throws: URLError.self) {
            try MediaFolderPath.applyingRoot("/new", to: ["monitored": false])
        }
    }

    @Test
    func posterURLsSupportReverseProxyPathsWithoutDuplicatingBase() {
        let base = "https://media.example/radarr/"
        #expect(ServerImageURL.resolve("/radarr/MediaCover/1/poster.jpg?v=2", serverURL: base)?.absoluteString == "https://media.example/radarr/MediaCover/1/poster.jpg?v=2")
        #expect(ServerImageURL.resolve("/MediaCover/1/poster.jpg", serverURL: base)?.absoluteString == "https://media.example/radarr/MediaCover/1/poster.jpg")
        #expect(ServerImageURL.resolve("MediaCover/1/poster.jpg", serverURL: base)?.absoluteString == "https://media.example/radarr/MediaCover/1/poster.jpg")
        #expect(ServerImageURL.resolve("https://images.example/poster.jpg", serverURL: base)?.host == "images.example")
        #expect(ServerImageURL.resolve("/poster.jpg", serverURL: "") == nil)
        #expect(ServerImageURL.resolve("file:///poster.jpg", serverURL: base) == nil)
        #expect(ServerImageURL.resolve("//other.example/poster.jpg", serverURL: base) == nil)
    }

    @Test
    func posterAuthenticationIsLimitedToConfiguredOriginAndPath() throws {
        let base = "https://media.example:443/radarr"
        #expect(ServerImageURL.matchesServer(try #require(URL(string: "https://media.example/radarr/poster.jpg")), serverURL: base))
        for candidate in [
            "https://media.example.evil/radarr/poster.jpg",
            "http://media.example/radarr/poster.jpg",
            "https://media.example:444/radarr/poster.jpg",
            "https://media.example/radarr-other/poster.jpg",
            "https://media.example/sonarr/poster.jpg",
            "https://media.example/radarr/../sonarr/poster.jpg"
        ] {
            #expect(!ServerImageURL.matchesServer(try #require(URL(string: candidate)), serverURL: base))
        }
    }

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
    func encryptedBackupRejectsUnsafePBKDFIterations() throws {
        let encrypted = EncryptedBackupSecrets(
            salt: Data(repeating: 1, count: 16),
            nonce: Data(repeating: 2, count: 12),
            ciphertext: Data(repeating: 3, count: 32),
            tag: Data(repeating: 4, count: 16),
            iterations: -1
        )

        do {
            _ = try BackupEncryptionService().decrypt(encrypted, passphrase: "test passphrase")
            Issue.record("Expected malformed backup to be rejected")
        } catch let error as BackupError {
            guard case .invalidBackupFile = error else {
                Issue.record("Unexpected backup error: \(error.localizedDescription)")
                return
            }
        }
    }

    @Test
    func forcedCacheRefreshSupersedesCancellationIgnoringRequest() async throws {
        let cache = CacheManager.shared
        let key = "tests.cache.supersede.\(UUID().uuidString)"
        defer { Task { await cache.remove(key) } }

        let original = Task {
            try await cache.fetchWithCache(key: key, ttl: 60) {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return "old"
            }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        let replacement = Task {
            try await cache.fetchWithCache(key: key, ttl: 60, bypassInFlight: true) {
                try await Task.sleep(nanoseconds: 50_000_000)
                return "new"
            }
        }

        #expect(try await replacement.value == "new")
        #expect(try await original.value == "new")
        let cached: String? = await cache.get(key)
        #expect(cached == "new")
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
    func widgetEventIdentityIsStableAcrossCalendarRebuilds() throws {
        let movie = Movie(
            id: 42,
            title: "Example Movie",
            year: 2026,
            overview: nil,
            runtime: 120,
            monitored: true,
            status: "released",
            images: []
        )
        let releaseDate = try #require(ISO8601DateFormatter().date(from: "2026-08-23T12:00:00Z"))
        let first = CalendarEvent(
            title: movie.title,
            date: releaseDate,
            type: .movieRelease(releaseType: .digital),
            source: .movie(movie),
            posterURL: nil,
            year: movie.year
        )
        let rebuilt = CalendarEvent(
            title: movie.title,
            date: releaseDate,
            type: .movieRelease(releaseType: .digital),
            source: .movie(movie),
            posterURL: nil,
            year: movie.year
        )

        #expect(first.id != rebuilt.id)
        #expect(WidgetEvent.from(calendarEvent: first)?.id == WidgetEvent.from(calendarEvent: rebuilt)?.id)
    }

    @Test
    func unraidDiskStatusMapsCurrentAPIValues() {
        #expect(DiskStatus(apiValue: "DISK_DSBL") == .disabled)
        #expect(DiskStatus(apiValue: "DISK_NP_MISSING") == .missing)
        #expect(DiskStatus(apiValue: "DISK_INVALID") == .error)
    }

    @Test
    func downloadsPollingFollowsVisibilityIncludingMoreMenuNavigation() {
        // Downloads can be visible through More without the parent selection
        // being 4. Polling deliberately has no parent tab-selection input.
        #expect(DownloadsPollingPolicy.refreshIntervalSeconds == 5)
        for visible in [false, true] {
            for activeQueue in [false, true] {
                for phase in [ScenePhase.active, .inactive, .background] {
                    for configured in [false, true] {
                        let result = DownloadsPollingPolicy.shouldPoll(
                            isViewVisible: visible,
                            isViewingActiveQueue: activeQueue,
                            scenePhase: phase,
                            isSabConfigured: configured
                        )
                        #expect(result == (visible && activeQueue && phase == .active && configured))
                    }
                }
            }
        }
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

    @Test @MainActor
    func addDefaultsPreserveTagsWhenTagEndpointIsUnavailable() {
        let store = makeDefaults(suffix: "add-default-tags")
        defer { clearDefaults(store) }
        store.defaults.set([2, 7], forKey: "addPreferences.radarr.tagIds")

        let preferences = AddMediaPreferences(defaults: store.defaults)
        let settings = preferences.radarrSettings(
            profiles: [RadarrQualityProfile(id: 1, name: "HD")],
            rootFolders: [RootFolder(id: 1, path: "/movies", freeSpace: nil, totalSpace: nil)],
            tags: nil
        )

        #expect(settings.tagIds == [2, 7])
    }

    @Test @MainActor
    func addDefaultsDiscardOnlyTagsConfirmedMissingByServer() {
        let store = makeDefaults(suffix: "add-default-tag-validation")
        defer { clearDefaults(store) }
        store.defaults.set([2, 7], forKey: "addPreferences.radarr.tagIds")

        let preferences = AddMediaPreferences(defaults: store.defaults)
        let settings = preferences.radarrSettings(
            profiles: [RadarrQualityProfile(id: 1, name: "HD")],
            rootFolders: [RootFolder(id: 1, path: "/movies", freeSpace: nil, totalSpace: nil)],
            tags: [MediaTag(id: 7, label: "keep")]
        )

        #expect(settings.tagIds == [7])
    }

    @Test @MainActor
    func legacyMovieMonitoringDefaultMigratesToRadarrMonitorOption() {
        let store = makeDefaults(suffix: "radarr-monitor-migration")
        defer { clearDefaults(store) }
        store.defaults.set(false, forKey: "addPreferences.radarr.monitored")

        let preferences = AddMediaPreferences(defaults: store.defaults)
        let settings = preferences.radarrSettings(
            profiles: [RadarrQualityProfile(id: 1, name: "HD")],
            rootFolders: [RootFolder(id: 1, path: "/movies", freeSpace: nil, totalSpace: nil)],
            tags: []
        )

        #expect(settings.monitorOption == .none)
        #expect(!settings.monitored)
    }

    @Test
    func sonarrLookupDecodesExistingLibraryIdentifier() throws {
        let data = """
        {"id":42,"tvdbId":121361,"title":"Example","year":2026,"images":[]}
        """.data(using: .utf8)!

        let lookup = try JSONDecoder().decode(TVShowLookup.self, from: data)

        #expect(lookup.sonarrId == 42)
        #expect(lookup.tvdbId == 121361)
    }

    @Test @MainActor
    func backupDocumentURLRoutesToSettingsRestoreFlow() {
        let handler = DeepLinkHandler.shared
        handler.clearPendingDestination()
        handler.clearPendingBackupURL()
        defer {
            handler.clearPendingDestination()
            handler.clearPendingBackupURL()
        }

        let url = URL(fileURLWithPath: "/tmp/MediaManager_Backup.mediabackup")
        handler.handle(url: url)

        #expect(handler.pendingDestination == .settings)
        #expect(handler.pendingBackupURL == url)
    }

    @Test @MainActor
    func showMatchingDoesNotConfuseRemakesOrDifferentTVDBIDs() {
        let library = LibraryStateManager()
        let original = TVShow(id: 1, title: "Example Show", year: 2004,
                              overview: nil, network: nil, status: "ended",
                              monitored: true, qualityProfileId: 1, images: [],
                              statistics: nil, tvdbId: 100)
        library.addShowLocally(original)

        #expect(library.isShowInLibrary(tvdbId: 100, name: "Alternate title", year: 2026))
        #expect(library.findShow(tvdbId: 100, name: "Alternate title", year: 2026)?.id == 1)
        #expect(!library.isShowInLibrary(tvdbId: 200, name: original.title, year: 2004))
        #expect(library.findShow(tvdbId: 200, name: original.title, year: 2004) == nil)
        #expect(!library.isShowInLibrary(name: original.title, year: 2026))
        #expect(library.findShow(byName: original.title, year: 2026) == nil)
        #expect(library.isShowInLibrary(tvdbId: nil, name: "EXAMPLE-SHOW", year: 2004))
        #expect(library.findShow(tvdbId: 0, name: "EXAMPLE-SHOW", year: nil)?.id == 1)
        #expect(library.isShowInLibrary(name: original.title, year: 0))
    }

    @Test @MainActor
    func recentlyAddedShowsSortMixedDatesAndInvalidateAfterUpdates() {
        let library = LibraryStateManager()
        func show(_ id: Int, _ date: String?) -> TVShow {
            TVShow(id: id, title: "Show \(id)", year: 2026, overview: nil,
                   network: nil, status: "continuing", monitored: true,
                   qualityProfileId: 1, images: [], statistics: nil, added: date)
        }
        library.addShowLocally(show(1, nil))
        library.addShowLocally(show(2, "2026-09-01T00:00:00Z"))
        library.addShowLocally(show(3, "2026-09-02T00:00:00.123Z"))
        #expect(library.recentlyAddedShows.map(\.id) == [3, 2, 1])
        library.updateShowLocally(show(1, "2026-09-03T00:00:00Z"))
        #expect(library.recentlyAddedShows.map(\.id) == [1, 3, 2])
        library.removeShowLocally(id: 3)
        #expect(library.recentlyAddedShows.map(\.id) == [1, 2])
    }

    @Test @MainActor
    func imageMemoryCostIncludesRetinaPixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
            }
        let cgImage = try #require(image.cgImage)
        #expect(ImageCacheManager.memoryCost(of: image) == cgImage.bytesPerRow * cgImage.height)
        #expect(ImageCacheManager.memoryCost(of: image) >= 30 * 60 * 4)
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

private final class UnraidMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [(Int, String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = Self.replies.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct UnraidCommandTests {
    @Test @MainActor
    func commandsPreserveIDsAndHandleCompatibilityFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnraidMockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = UnraidService(session: session, credentials: {
            (URL(string: "https://unraid.invalid/graphql")!, "test-key")
        })
        let success = #"{"data":{"docker":{"result":{"id":"docker:abc_123","state":"RUNNING","status":"Up"}}}}"#
        UnraidMockProtocol.requests = []
        UnraidMockProtocol.replies = [(200, success)]
        try await service.restartContainer(id: "docker:abc_123")
        #expect(UnraidMockProtocol.requests.count == 1)
        let request = try #require(UnraidMockProtocol.requests.first)
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        let requestBody = try #require(body)
        let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect((json["variables"] as? [String: String])?["id"] == "docker:abc_123")
        #expect((json["query"] as? String)?.contains("result: restart(id: $id)") == true)
        #expect(request.timeoutInterval == 120)

        UnraidMockProtocol.requests = []
        UnraidMockProtocol.replies = [
            (400, #"{"errors":[{"message":"Cannot query field \"restart\" on type \"DockerMutations\"."}]}"#),
            (200, success), (200, success)
        ]
        try await service.restartContainer(id: "docker:abc_123")
        #expect(UnraidMockProtocol.requests.count == 3)

        for failure in [
            #"{"errors":[{"message":"Forbidden"}]}"#,
            #"{"data":null}"#,
            #"{"data":{"docker":{}},"errors":[{"message":"Operation failed"}]}"#
        ] {
            UnraidMockProtocol.requests = []
            UnraidMockProtocol.replies = [(200, failure)]
            await #expect(throws: (any Error).self) {
                try await service.restartContainer(id: "docker:abc_123")
            }
            #expect(UnraidMockProtocol.requests.count == 1)
        }
        UnraidMockProtocol.replies = [(200, #"{"data":{"vm":{"result":false}}}"#)]
        await #expect(throws: (any Error).self) {
            try await service.startVm(id: "vm:example-uuid")
        }
    }
}

extension UnraidCommandTests {
    private static var snapshot: String {
        #"{"data":{"vars":{"version":"7.3.0"},"info":{"os":{"hostname":"tower","uptime":"2026-09-01T00:00:00Z"},"cpu":{"brand":"CPU","cores":8}},"metrics":{"cpu":{"percentTotal":12.5},"memory":{"total":"34359738368","used":8589934592,"free":"25769803776","available":"30000000000","percentTotal":12.7}},"array":{"state":"STOPPED","capacity":{"kilobytes":{"total":"1000","used":"250","free":"750"}},"disks":[{"id":"disk:1","name":null,"size":null,"status":null,"temp":null,"type":"DATA"}],"caches":[],"parities":[],"boot":{"id":"disk:boot","name":"boot","size":"1024","status":"DISK_OK","type":"BOOT"}},"docker":{"containers":[]},"vms":{"domains":[{"id":"vm:123","name":null,"state":"SHUTOFF"}]}}}"#
    }

    @Test @MainActor
    func snapshotHandlesNullableFieldsAndScopesCacheToCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnraidMockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var server = URL(string: "https://tower.invalid/graphql")!
        var key = "first-key"
        let service = UnraidService(session: session, credentials: { (server, key) })
        UnraidMockProtocol.requests = []
        UnraidMockProtocol.replies = [(200, Self.snapshot)]
        async let first = service.fetchAllData()
        async let second = service.fetchAllData()
        let (data, other) = try await (first, second)
        #expect(UnraidMockProtocol.requests.count == 1)
        #expect(data.system == other.system)
        #expect(data.system.memory.total == 34359738368)
        #expect(data.system.memory.available == 30000000000)
        #expect(data.array.disks.first?.size == 0)
        #expect(data.array.disks.first?.status == .unknown)
        #expect(data.array.disks.last?.type == .flash)
        #expect(data.array.capacity.total == 1_000_000)
        #expect(data.vms.first?.id == "vm:123")
        #expect(data.vms.first?.name == "Unnamed VM")
        _ = try await service.fetchAllData()
        #expect(UnraidMockProtocol.requests.count == 1)

        UnraidMockProtocol.replies = [(200, Self.snapshot)]
        _ = try await service.fetchAllData(forceRefresh: true)
        #expect(UnraidMockProtocol.requests.count == 2)
        key = "replacement-key"
        UnraidMockProtocol.replies = [(200, Self.snapshot)]
        _ = try await service.fetchAllData()
        #expect(UnraidMockProtocol.requests.count == 3)
        #expect(UnraidMockProtocol.requests.last?.value(forHTTPHeaderField: "x-api-key") == key)
        server = URL(string: "https://other-tower.invalid/graphql")!
        UnraidMockProtocol.replies = [(200, Self.snapshot)]
        _ = try await service.fetchAllData()
        #expect(UnraidMockProtocol.requests.count == 4)
        #expect(UnraidMockProtocol.requests.last?.url == server)
        await service.invalidateCache()
        UnraidMockProtocol.replies = [(200, Self.snapshot)]
        _ = try await service.fetchAllData()
        #expect(UnraidMockProtocol.requests.count == 5)
    }

    @Test @MainActor
    func endpointsRetryPolicyAndOverflowAreSafe() throws {
        #expect(try UnraidService.graphQLURL(from: " https://tower:8443/ ").absoluteString == "https://tower:8443/graphql")
        #expect(try UnraidService.graphQLURL(from: "https://tower/proxy/graphql/").absoluteString == "https://tower/proxy/graphql")
        #expect(try UnraidService.graphQLURL(from: "http://[::1]:8080").absoluteString == "http://[::1]:8080/graphql")
        for invalid in ["tower", "file:///tmp/server", "https://user:password@tower", "https://tower?key=secret", "https://tower/#fragment"] {
            #expect(throws: (any Error).self) { try UnraidService.graphQLURL(from: invalid) }
        }
        #expect(!UnraidService.shouldRetryRead(UnraidError.unauthorized))
        #expect(!UnraidService.shouldRetryRead(UnraidError.forbidden))
        #expect(!UnraidService.shouldRetryRead(UnraidError.graphQLError("Unsupported field")))
        #expect(!UnraidService.shouldRetryRead(CancellationError()))
        #expect(UnraidService.shouldRetryRead(UnraidError.httpError(429)))
        #expect(UnraidService.shouldRetryRead(UnraidError.httpError(503)))
        #expect(UnraidService.shouldRetryRead(URLError(.timedOut)))
        #expect(UnraidService.saturatingKilobytes(Int64.max) == Int64.max)
        #expect(UnraidService.saturatingKilobytes(-1) == 0)
    }
}

extension UnraidCommandTests {
    @Test @MainActor
    func missingMetricsRemainUnavailable() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnraidMockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = UnraidService(session: session)
        UnraidMockProtocol.replies = [(200, #"{"data":{"vars":{"version":"7.3.0"},"info":{"os":{"hostname":"tower","uptime":"2026-09-01T00:00:00Z"},"cpu":{"brand":"CPU","cores":8}},"metrics":null}}"#)]
        let info = try await service.testConnection(url: "https://tower.invalid/graphql/", apiKey: "test-key")
        #expect(info.cpu.usage == nil)
        #expect(info.memory.total == 0)
        #expect(info.memory.usagePercentage == 0)
    }
}
