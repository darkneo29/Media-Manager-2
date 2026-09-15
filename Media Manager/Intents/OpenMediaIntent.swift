import AppIntents
import Foundation

struct OpenMovieIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Movie"
    @Parameter(title: "Movie") var target: MovieSearchResultEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let movies = try await RadarrService.shared.fetchMovies()
        guard let movie = movies.first(where: { $0.tmdbId == target.id }) else {
            throw MediaNavigationError.notInLibrary
        }
        DeepLinkHandler.shared.pendingDestination = .movie(id: movie.id)
        return .result()
    }
}

struct OpenTVShowIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open TV Show"
    @Parameter(title: "TV Show") var target: TVShowSearchResultEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let shows = try await SonarrService.shared.fetchShows()
        guard let show = shows.first(where: { $0.tvdbId == target.id }) else {
            throw MediaNavigationError.notInLibrary
        }
        DeepLinkHandler.shared.pendingDestination = .tvShow(id: show.id)
        return .result()
    }
}

enum MediaNavigationError: LocalizedError {
    case notInLibrary
    var errorDescription: String? { "This title is no longer in your configured library." }
}

/// Entity parameters let Shortcuts and on-screen context carry an exact catalog ID.
struct AddSelectedMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Selected Movie"
    static var description = IntentDescription("Add a specific movie to Radarr using its catalog identity.")
    @Parameter(title: "Movie", requestValueDialog: "Which movie would you like to add?") var movie: MovieSearchResultEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var intent = QuickAddMovieIntent()
        intent.searchTerm = "tmdb:\(movie.id)"
        return try await intent.perform()
    }
}

struct AddSelectedTVShowIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Selected TV Show"
    static var description = IntentDescription("Add a specific TV show to Sonarr using its catalog identity.")
    @Parameter(title: "TV Show", requestValueDialog: "Which TV show would you like to add?") var show: TVShowSearchResultEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var intent = QuickAddTVShowIntent()
        intent.searchTerm = "tvdb:\(show.id)"
        return try await intent.perform()
    }
}

#if os(iOS)
@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchMediaLibraryIntent: ShowInAppSearchResultsIntent {
    static var title: LocalizedStringResource = "Search Media Library"
    static var searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkHandler.shared.pendingLibrarySearch = criteria.term
        return .result()
    }
}
#endif
