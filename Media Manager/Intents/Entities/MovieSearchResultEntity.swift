import AppIntents
import Foundation

/// Entity representing a movie search result for App Intents
struct MovieSearchResultEntity: AppEntity {
    /// Unique identifier (TMDB ID)
    var id: Int

    /// Movie title
    @Property(title: "Title")
    var title: String

    /// Release year
    @Property(title: "Year")
    var year: Int

    /// Movie overview/description
    @Property(title: "Overview")
    var overview: String?

    /// Runtime in minutes
    @Property(title: "Runtime in Minutes")
    var runtime: Int

    /// Type display representation for the entity
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Movie"

    /// How the entity is displayed in UI
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(year)\(runtime > 0 ? " - \(runtime) min" : "")"
        )
    }

    /// Default query for finding movies
    static var defaultQuery = MovieSearchResultStringQuery()

    /// Initialize from MovieLookup
    init(from lookup: MovieLookup) {
        self.id = lookup.tmdbId
        self.title = lookup.title
        self.year = lookup.year
        self.overview = lookup.overview
        self.runtime = lookup.runtime
    }

    /// Basic initializer
    init(id: Int, title: String, year: Int, overview: String? = nil, runtime: Int = 0) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.runtime = runtime
    }
}

/// Resolve saved Shortcuts parameters by their authoritative catalog ID.
struct MovieSearchResultQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [MovieSearchResultEntity] {
        guard ConfigurationManager.shared.isRadarrConfigured else { return [] }
        return try await MediaEntityResolution.resolve(identifiers) { id in
            let results = try await RadarrService.shared.searchMovies(term: "tmdb:\(id)")
            return results.first(where: { $0.tmdbId == id }).map { MovieSearchResultEntity(from: $0) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [MovieSearchResultEntity] {
        guard ConfigurationManager.shared.isRadarrConfigured else { return [] }
        return try await RadarrService.shared.fetchMovies().prefix(20).compactMap { item in
            guard let id = item.tmdbId, id > 0 else { return nil }
            return MovieSearchResultEntity(id: id, title: item.title, year: item.year, overview: item.overview, runtime: item.runtime)
        }
    }
}

struct MovieSearchResultStringQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [MovieSearchResultEntity] {
        try await MovieSearchResultQuery().entities(for: identifiers)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MovieSearchResultEntity] {
        let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ConfigurationManager.shared.isRadarrConfigured, !term.isEmpty else { return [] }
        let results = try await RadarrService.shared.searchMovies(term: term)
        return MediaEntityResolution.exactCatalogMatches(results, term: term, prefix: "tmdb", id: \.tmdbId).map { MovieSearchResultEntity(from: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MovieSearchResultEntity] {
        try await MovieSearchResultQuery().suggestedEntities()
    }
}
