import Combine
import Foundation

/// Centralized configuration manager that caches UserDefaults values
/// Reduces repeated UserDefaults lookups which are slower than in-memory access
@MainActor
final class ConfigurationManager: ObservableObject {
    static let shared = ConfigurationManager(credentialStore: .shared)

    // MARK: - Cached Configuration Values

    @Published private(set) var radarrURL: String = ""
    @Published private(set) var radarrAPIKey: String = ""
    @Published private(set) var sonarrURL: String = ""
    @Published private(set) var sonarrAPIKey: String = ""
    @Published private(set) var sabnzbURL: String = ""
    @Published private(set) var sabnzbAPIKey: String = ""
    @Published private(set) var tmdbAccessToken: String = ""
    @Published private(set) var unraidURL: String = ""
    @Published private(set) var unraidAPIKey: String = ""

    private let credentialStore: CredentialStore

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let radarrURL = "radarrURL"
        static let sonarrURL = "sonarrURL"
        static let sabnzbURL = "sabnzbURL"
        static let unraidURL = "unraidURL"
    }

    private init(credentialStore: CredentialStore) {
        self.credentialStore = credentialStore
        credentialStore.migrateLegacyCredentialsIfNeeded()
        loadConfiguration()
        setupNotificationObserver()
    }

    // MARK: - Public Properties

    /// Radarr API base URL (with /api/v3 suffix)
    var radarrBaseURL: String {
        "\(radarrURL)/api/v3"
    }

    /// Sonarr API base URL (with /api/v3 suffix)
    var sonarrBaseURL: String {
        "\(sonarrURL)/api/v3"
    }

    /// SabNZB API base URL (with /api suffix)
    var sabnzbBaseURL: String {
        "\(sabnzbURL)/api"
    }

    /// Check if Unraid is configured
    var isUnraidConfigured: Bool {
        !unraidURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !unraidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Configuration Loading

    /// Load all configuration values from UserDefaults
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        radarrURL = defaults.string(forKey: Keys.radarrURL) ?? ""
        radarrAPIKey = credentialStore.string(for: .radarrAPIKey)
        sonarrURL = defaults.string(forKey: Keys.sonarrURL) ?? ""
        sonarrAPIKey = credentialStore.string(for: .sonarrAPIKey)
        sabnzbURL = defaults.string(forKey: Keys.sabnzbURL) ?? ""
        sabnzbAPIKey = credentialStore.string(for: .sabnzbAPIKey)
        tmdbAccessToken = credentialStore.string(for: .tmdbAccessToken)
        unraidURL = defaults.string(forKey: Keys.unraidURL) ?? ""
        unraidAPIKey = credentialStore.string(for: .unraidAPIKey)
    }

    /// Refresh cached configuration from UserDefaults
    /// Call this when settings are updated
    func refreshConfiguration(invalidateCaches: Bool = false) {
        loadConfiguration()
        // Also refresh ImageCacheManager's configuration
        Task {
            await ImageCacheManager.shared.refreshConfiguration()
            if invalidateCaches {
                await CacheManager.shared.clearAll()
                await ImageCacheManager.shared.clearAll()
                WidgetDataService.shared.clearWidgetData()
            }
        }
    }

    // MARK: - Notification Observer

    /// Setup observer for UserDefaults changes
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadConfiguration()
            }
        }
    }

    func saveRadarr(url: String, apiKey: String) throws {
        let defaults = UserDefaults.standard
        defaults.set(Self.normalizedServerURL(url), forKey: Keys.radarrURL)
        try credentialStore.set(apiKey, for: .radarrAPIKey)
        refreshConfiguration()
        invalidateRadarrState()
    }

    func saveSonarr(url: String, apiKey: String) throws {
        let defaults = UserDefaults.standard
        defaults.set(Self.normalizedServerURL(url), forKey: Keys.sonarrURL)
        try credentialStore.set(apiKey, for: .sonarrAPIKey)
        refreshConfiguration()
        invalidateSonarrState()
    }

    func saveSabNZB(url: String, apiKey: String) throws {
        let defaults = UserDefaults.standard
        defaults.set(Self.normalizedServerURL(url), forKey: Keys.sabnzbURL)
        try credentialStore.set(apiKey, for: .sabnzbAPIKey)
        refreshConfiguration()
    }

    func saveTMDBToken(_ token: String) throws {
        try credentialStore.set(token, for: .tmdbAccessToken)
        refreshConfiguration()
        invalidateTMDBState()
    }

    func saveUnraid(url: String, apiKey: String) throws {
        let defaults = UserDefaults.standard
        defaults.set(Self.normalizedServerURL(url), forKey: Keys.unraidURL)
        try credentialStore.set(apiKey, for: .unraidAPIKey)
        refreshConfiguration()
    }

    // MARK: - Configuration Validation

    /// Check if Radarr is configured
    var isRadarrConfigured: Bool {
        !radarrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !radarrAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if Sonarr is configured
    var isSonarrConfigured: Bool {
        !sonarrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sonarrAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if SabNZB is configured
    var isSabNZBConfigured: Bool {
        !sabnzbURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sabnzbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if TMDB is configured
    var isTMDBConfigured: Bool {
        !tmdbAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func normalizedServerURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.count > 1 && normalized.hasSuffix("/") && !normalized.hasSuffix("://") {
            normalized.removeLast()
        }
        return normalized
    }

    private func invalidateRadarrState() {
        Task {
            await RadarrService.shared.invalidateCache()
            await ImageCacheManager.shared.clearAll()
            await LibraryStateManager.shared.invalidateMovies()
        }
    }

    private func invalidateSonarrState() {
        Task {
            await SonarrService.shared.invalidateCache()
            await ImageCacheManager.shared.clearAll()
            await LibraryStateManager.shared.invalidateShows()
        }
    }

    private func invalidateTMDBState() {
        Task {
            await TMDBService.shared.invalidateCache()
        }
    }
}

struct RadarrAddSettings {
    var qualityProfileId: Int
    var rootFolderPath: String
    var minimumAvailability: RadarrMinimumAvailability
    var monitored: Bool
    var searchForMovie: Bool
    var tagIds: [Int]
}

struct SonarrAddSettings {
    var qualityProfileId: Int
    var rootFolderPath: String
    var monitorOption: MonitorOption
    var monitored: Bool
    var monitorNewItems: SonarrNewItemMonitor
    var seriesType: SonarrSeriesType
    var seasonFolder: Bool
    var searchForMissingEpisodes: Bool
    var searchForCutoffUnmetEpisodes: Bool
    var tagIds: [Int]
}

@MainActor
final class AddMediaPreferences {
    static let shared = AddMediaPreferences()

    private let defaults: UserDefaults

    private enum Keys {
        static let radarrQualityProfileId = "addPreferences.radarr.qualityProfileId"
        static let radarrRootFolderPath = "addPreferences.radarr.rootFolderPath"
        static let radarrMinimumAvailability = "addPreferences.radarr.minimumAvailability"
        static let radarrMonitored = "addPreferences.radarr.monitored"
        static let radarrSearchForMovie = "addPreferences.radarr.searchForMovie"
        static let radarrTagIds = "addPreferences.radarr.tagIds"

        static let sonarrQualityProfileId = "addPreferences.sonarr.qualityProfileId"
        static let sonarrRootFolderPath = "addPreferences.sonarr.rootFolderPath"
        static let sonarrMonitorOption = "addPreferences.sonarr.monitorOption"
        static let sonarrMonitored = "addPreferences.sonarr.monitored"
        static let sonarrMonitorNewItems = "addPreferences.sonarr.monitorNewItems"
        static let sonarrSeriesType = "addPreferences.sonarr.seriesType"
        static let sonarrSeasonFolder = "addPreferences.sonarr.seasonFolder"
        static let sonarrSearchForMissing = "addPreferences.sonarr.searchForMissing"
        static let sonarrSearchForCutoffUnmet = "addPreferences.sonarr.searchForCutoffUnmet"
        static let sonarrTagIds = "addPreferences.sonarr.tagIds"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func radarrSettings(profiles: [RadarrQualityProfile], rootFolders: [RootFolder], tags: [MediaTag]) -> RadarrAddSettings {
        RadarrAddSettings(
            qualityProfileId: preferredRadarrQualityProfileId(profiles),
            rootFolderPath: preferredRadarrRootFolderPath(rootFolders),
            minimumAvailability: RadarrMinimumAvailability(rawValue: defaults.string(forKey: Keys.radarrMinimumAvailability) ?? "") ?? .released,
            monitored: bool(for: Keys.radarrMonitored, defaultValue: true),
            searchForMovie: bool(for: Keys.radarrSearchForMovie, defaultValue: true),
            tagIds: validatedTagIds(defaults.array(forKey: Keys.radarrTagIds) as? [Int] ?? [], availableTags: tags)
        )
    }

    func saveRadarr(_ settings: RadarrAddSettings) {
        defaults.set(settings.qualityProfileId, forKey: Keys.radarrQualityProfileId)
        defaults.set(settings.rootFolderPath, forKey: Keys.radarrRootFolderPath)
        defaults.set(settings.minimumAvailability.rawValue, forKey: Keys.radarrMinimumAvailability)
        defaults.set(settings.monitored, forKey: Keys.radarrMonitored)
        defaults.set(settings.searchForMovie, forKey: Keys.radarrSearchForMovie)
        defaults.set(settings.tagIds.sorted(), forKey: Keys.radarrTagIds)
    }

    func sonarrSettings(profiles: [QualityProfile], rootFolders: [SonarrRootFolder], tags: [MediaTag]) -> SonarrAddSettings {
        SonarrAddSettings(
            qualityProfileId: preferredSonarrQualityProfileId(profiles),
            rootFolderPath: preferredSonarrRootFolderPath(rootFolders),
            monitorOption: MonitorOption.normalized(rawValue: defaults.string(forKey: Keys.sonarrMonitorOption)),
            monitored: bool(for: Keys.sonarrMonitored, defaultValue: true),
            monitorNewItems: SonarrNewItemMonitor(rawValue: defaults.string(forKey: Keys.sonarrMonitorNewItems) ?? "") ?? .all,
            seriesType: SonarrSeriesType(rawValue: defaults.string(forKey: Keys.sonarrSeriesType) ?? "") ?? .standard,
            seasonFolder: bool(for: Keys.sonarrSeasonFolder, defaultValue: true),
            searchForMissingEpisodes: bool(for: Keys.sonarrSearchForMissing, defaultValue: true),
            searchForCutoffUnmetEpisodes: bool(for: Keys.sonarrSearchForCutoffUnmet, defaultValue: false),
            tagIds: validatedTagIds(defaults.array(forKey: Keys.sonarrTagIds) as? [Int] ?? [], availableTags: tags)
        )
    }

    func saveSonarr(_ settings: SonarrAddSettings) {
        defaults.set(settings.qualityProfileId, forKey: Keys.sonarrQualityProfileId)
        defaults.set(settings.rootFolderPath, forKey: Keys.sonarrRootFolderPath)
        defaults.set(settings.monitorOption.rawValue, forKey: Keys.sonarrMonitorOption)
        defaults.set(settings.monitored, forKey: Keys.sonarrMonitored)
        defaults.set(settings.monitorNewItems.rawValue, forKey: Keys.sonarrMonitorNewItems)
        defaults.set(settings.seriesType.rawValue, forKey: Keys.sonarrSeriesType)
        defaults.set(settings.seasonFolder, forKey: Keys.sonarrSeasonFolder)
        defaults.set(settings.searchForMissingEpisodes, forKey: Keys.sonarrSearchForMissing)
        defaults.set(settings.searchForCutoffUnmetEpisodes, forKey: Keys.sonarrSearchForCutoffUnmet)
        defaults.set(settings.tagIds.sorted(), forKey: Keys.sonarrTagIds)
    }

    private func preferredRadarrQualityProfileId(_ profiles: [RadarrQualityProfile]) -> Int {
        let saved = defaults.integer(forKey: Keys.radarrQualityProfileId)
        if saved > 0, profiles.contains(where: { $0.id == saved }) {
            return saved
        }
        return profiles.first(where: { $0.name.localizedCaseInsensitiveContains("1080") || $0.name.localizedCaseInsensitiveContains("HD") })?.id
            ?? profiles.first?.id
            ?? 1
    }

    private func preferredSonarrQualityProfileId(_ profiles: [QualityProfile]) -> Int {
        let saved = defaults.integer(forKey: Keys.sonarrQualityProfileId)
        if saved > 0, profiles.contains(where: { $0.id == saved }) {
            return saved
        }
        return profiles.first(where: { $0.id == 6 || $0.name.localizedCaseInsensitiveContains("720p/1080p") })?.id
            ?? profiles.first(where: { $0.name.localizedCaseInsensitiveContains("HD") || $0.name.localizedCaseInsensitiveContains("1080") })?.id
            ?? profiles.first?.id
            ?? 1
    }

    private func preferredRadarrRootFolderPath(_ rootFolders: [RootFolder]) -> String {
        let saved = defaults.string(forKey: Keys.radarrRootFolderPath) ?? ""
        if rootFolders.contains(where: { $0.path == saved }) {
            return saved
        }
        return rootFolders.first?.path ?? "/movies/"
    }

    private func preferredSonarrRootFolderPath(_ rootFolders: [SonarrRootFolder]) -> String {
        let saved = defaults.string(forKey: Keys.sonarrRootFolderPath) ?? ""
        if rootFolders.contains(where: { $0.path == saved }) {
            return saved
        }
        return rootFolders.first?.path ?? "/tv/"
    }

    private func bool(for key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func validatedTagIds(_ tagIds: [Int], availableTags: [MediaTag]) -> [Int] {
        guard !availableTags.isEmpty else { return [] }
        let availableIds = Set(availableTags.map(\.id))
        return tagIds.filter { availableIds.contains($0) }
    }
}
