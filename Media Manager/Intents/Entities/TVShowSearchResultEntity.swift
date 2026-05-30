import AppIntents
import Foundation

/// Entity representing a TV show search result for App Intents
struct TVShowSearchResultEntity: AppEntity {
    /// Unique identifier (TVDB ID)
    var id: Int

    /// Show title
    var title: String

    /// First aired year
    var year: Int

    /// Show overview/description
    var overview: String?

    /// Number of seasons
    var seasonCount: Int

    /// Network name
    var network: String?

    /// Type display representation for the entity
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV Show"

    /// How the entity is displayed in UI
    var displayRepresentation: DisplayRepresentation {
        var subtitle = "\(year)"
        if seasonCount > 0 {
            subtitle += " - \(seasonCount) Season\(seasonCount != 1 ? "s" : "")"
        }
        if let network = network, !network.isEmpty {
            subtitle += " - \(network)"
        }

        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }

    /// Default query for finding TV shows
    static var defaultQuery = TVShowSearchResultQuery()

    /// Initialize from TVShowLookup
    init(from lookup: TVShowLookup) {
        self.id = lookup.tvdbId
        self.title = lookup.title
        self.year = lookup.year
        self.overview = lookup.overview
        self.seasonCount = lookup.seasonCount
        self.network = lookup.network
    }

    /// Basic initializer
    init(id: Int, title: String, year: Int, overview: String? = nil, seasonCount: Int = 0, network: String? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.seasonCount = seasonCount
        self.network = network
    }
}

/// Query for searching TV shows via Sonarr
struct TVShowSearchResultQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [TVShowSearchResultEntity] {
        // Return empty - suggestedEntities is the main entry point
        return []
    }

    @MainActor
    func suggestedEntities() async throws -> [TVShowSearchResultEntity] {
        // Return empty suggestions - user must search
        return []
    }
}

/// String-based query for searching TV shows by title
struct TVShowSearchResultStringQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [TVShowSearchResultEntity] {
        return []
    }

    @MainActor
    func entities(matching string: String) async throws -> [TVShowSearchResultEntity] {
        let config = ConfigurationManager.shared

        guard config.isSonarrConfigured else {
            return []
        }

        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            let results = try await SonarrService.shared.searchShows(term: string)
            return results.map { TVShowSearchResultEntity(from: $0) }
        } catch {
            return []
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [TVShowSearchResultEntity] {
        return []
    }
}
