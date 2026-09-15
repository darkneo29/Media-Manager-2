import AppIntents
import Foundation

/// Entity representing a TV show search result for App Intents
struct TVShowSearchResultEntity: AppEntity {
    /// Unique identifier (TVDB ID)
    var id: Int

    /// Show title
    @Property(title: "Title")
    var title: String

    /// First aired year
    @Property(title: "Year")
    var year: Int

    /// Show overview/description
    @Property(title: "Overview")
    var overview: String?

    /// Number of seasons
    @Property(title: "Seasons")
    var seasonCount: Int

    /// Network name
    @Property(title: "Network")
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
    static var defaultQuery = TVShowSearchResultStringQuery()

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

/// Resolve saved Shortcuts parameters by their authoritative catalog ID.
struct TVShowSearchResultQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [TVShowSearchResultEntity] {
        guard ConfigurationManager.shared.isSonarrConfigured else { return [] }
        return try await MediaEntityResolution.resolve(identifiers) { id in
            let results = try await SonarrService.shared.searchShows(term: "tvdb:\(id)")
            return results.first(where: { $0.tvdbId == id }).map { TVShowSearchResultEntity(from: $0) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [TVShowSearchResultEntity] {
        guard ConfigurationManager.shared.isSonarrConfigured else { return [] }
        return try await SonarrService.shared.fetchShows().prefix(20).compactMap { item in
            guard let id = item.tvdbId, id > 0 else { return nil }
            return TVShowSearchResultEntity(id: id, title: item.title, year: item.year, overview: item.overview, seasonCount: item.seasonCount, network: item.network)
        }
    }
}

struct TVShowSearchResultStringQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [TVShowSearchResultEntity] {
        try await TVShowSearchResultQuery().entities(for: identifiers)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TVShowSearchResultEntity] {
        let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConfigurationManager.shared.isSonarrConfigured, !term.isEmpty else { return [] }
        let results = try await SonarrService.shared.searchShows(term: term)
        return MediaEntityResolution.exactCatalogMatches(results, term: term, prefix: "tvdb", id: \.tvdbId).map { TVShowSearchResultEntity(from: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TVShowSearchResultEntity] {
        try await TVShowSearchResultQuery().suggestedEntities()
    }
}
