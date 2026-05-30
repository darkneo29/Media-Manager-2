import AppIntents
import Foundation

/// Intent to get library statistics (movie and TV show counts)
struct GetLibraryStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Library Stats"
    static var description = IntentDescription("Gets statistics about your movie and TV show library including counts and monitored items.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        let radarrConfigured = config.isRadarrConfigured
        let sonarrConfigured = config.isSonarrConfigured

        guard radarrConfigured || sonarrConfigured else {
            return .result(
                value: "No services configured",
                dialog: "Neither Radarr nor Sonarr is configured. Please set up at least one service in the app settings."
            )
        }

        var movieStats: (total: Int, monitored: Int, available: Int)? = nil
        var showStats: (total: Int, monitored: Int, episodes: Int)? = nil

        // Fetch movie stats if Radarr is configured
        if radarrConfigured {
            do {
                let movies = try await RadarrService.shared.fetchMovies()
                let monitored = movies.filter { $0.monitored }.count
                let available = movies.filter { $0.status == "released" }.count
                movieStats = (total: movies.count, monitored: monitored, available: available)
            } catch {
                // Continue with TV shows
            }
        }

        // Fetch TV show stats if Sonarr is configured
        if sonarrConfigured {
            do {
                let shows = try await SonarrService.shared.fetchShows()
                let monitored = shows.filter { $0.monitored }.count
                let totalEpisodes = shows.reduce(0) { $0 + ($1.statistics?.totalEpisodeCount ?? 0) }
                showStats = (total: shows.count, monitored: monitored, episodes: totalEpisodes)
            } catch {
                // Continue
            }
        }

        var parts: [String] = []

        if let movies = movieStats {
            parts.append("\(movies.total) movies (\(movies.monitored) monitored, \(movies.available) available)")
        }

        if let shows = showStats {
            parts.append("\(shows.total) TV shows (\(shows.monitored) monitored, \(shows.episodes) total episodes)")
        }

        if parts.isEmpty {
            return .result(
                value: "Could not fetch library stats",
                dialog: "Failed to fetch library statistics. Please check your server connections."
            )
        }

        let summary = "Your library contains: " + parts.joined(separator: " and ")

        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: summary)
        )
    }
}
