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
