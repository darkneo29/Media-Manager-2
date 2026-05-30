import AppIntents
import Foundation

/// Entity representing a movie search result for App Intents
struct MovieSearchResultEntity: AppEntity {
    /// Unique identifier (TMDB ID)
    var id: Int

    /// Movie title
    var title: String

    /// Release year
    var year: Int

    /// Movie overview/description
    var overview: String?

    /// Runtime in minutes
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
    static var defaultQuery = MovieSearchResultQuery()

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

/// Query for searching movies via Radarr
struct MovieSearchResultQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [MovieSearchResultEntity] {
        // This would require fetching by ID, but Radarr search is by term
        // Return empty for now - the suggestedEntities is the main entry point
        return []
    }

    @MainActor
    func suggestedEntities() async throws -> [MovieSearchResultEntity] {
        // Return empty suggestions - user must search
        return []
    }
}

/// String-based query for searching movies by title
struct MovieSearchResultStringQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [MovieSearchResultEntity] {
        return []
    }

    @MainActor
    func entities(matching string: String) async throws -> [MovieSearchResultEntity] {
        let config = ConfigurationManager.shared

        guard config.isRadarrConfigured else {
            return []
        }

        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            let results = try await RadarrService.shared.searchMovies(term: string)
            return results.map { MovieSearchResultEntity(from: $0) }
        } catch {
            return []
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [MovieSearchResultEntity] {
        return []
    }
}
