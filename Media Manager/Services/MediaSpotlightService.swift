import AppIntents
import SwiftUI
#if os(iOS)
import CoreSpotlight
import OSLog

@available(iOS 18.0, *)
extension MovieSearchResultEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .movie)
        attributes.title = title
        attributes.contentDescription = overview
        attributes.keywords = ["Movie", "Radarr", String(year)]
        if #available(iOS 27.0, *) { attributes.relatedAppEntityIdentifier = EntityIdentifier(for: self) }
        return attributes
    }
}

@available(iOS 18.0, *)
extension TVShowSearchResultEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .movie)
        attributes.title = title
        attributes.contentDescription = overview
        attributes.keywords = ["TV show", "Sonarr", String(year), network ?? ""]
        if #available(iOS 27.0, *) { attributes.relatedAppEntityIdentifier = EntityIdentifier(for: self) }
        return attributes
    }
}

/// Index only library metadata, never server addresses, paths, or credentials.
@MainActor
final class MediaSpotlightService {
    static let shared = MediaSpotlightService()
    private var pending: Task<Void, Never>?
    private var hasRebuiltIndex = false
    private var indexedMovies: [Int: [String]] = [:]
    private var indexedShows: [Int: [String]] = [:]

    @available(iOS 27.0, *)
    func search(_ text: String) async throws -> [EntityIdentifier] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        await pending?.value
        try Task.checkCancellation()
        let context = CSUserQueryContext()
        context.enableRankedResults = true
        context.disableSemanticSearch = false
        context.maxResultCount = 100
        context.maxSuggestionCount = 0
        let query = CSUserQuery(userQueryString: term, userQueryContext: context)
        defer { query.cancel() }
        var identifiers: [EntityIdentifier] = []
        for try await response in query.responses {
            try Task.checkCancellation()
            if case let .item(result) = response,
               let identifier = result.item.relatedAppEntityIdentifier {
                identifiers.append(identifier)
            }
        }
        return identifiers
    }

    func update(movies: [Movie], shows: [TVShow]) {
        guard #available(iOS 27.0, *) else { return }
        let previous = pending
        pending = Task {
            // Serialize replacements so an older refresh cannot restore deleted titles.
            await previous?.value
            do {
                let index = CSSearchableIndex.default()
                let movieEntities = movies.compactMap(MovieSearchResultEntity.init(libraryMovie:))
                let showEntities = shows.compactMap(TVShowSearchResultEntity.init(libraryShow:))
                let movieSignatures = Dictionary(movieEntities.map { ($0.id, [$0.title, String($0.year), $0.overview ?? "", String($0.runtime)]) }, uniquingKeysWith: { _, latest in latest })
                let showSignatures = Dictionary(showEntities.map { ($0.id, [$0.title, String($0.year), $0.overview ?? "", String($0.seasonCount), $0.network ?? ""]) }, uniquingKeysWith: { _, latest in latest })
                if !hasRebuiltIndex {
                    // Remove stale entries left by the previous app session.
                    try await index.deleteAppEntities(ofType: MovieSearchResultEntity.self)
                    try await index.deleteAppEntities(ofType: TVShowSearchResultEntity.self)
                    indexedMovies = [:]
                    indexedShows = [:]
                }
                let removedMovies = indexedMovies.keys.filter { movieSignatures[$0] == nil }
                let removedShows = indexedShows.keys.filter { showSignatures[$0] == nil }
                if !removedMovies.isEmpty { try await index.deleteAppEntities(identifiedBy: removedMovies, ofType: MovieSearchResultEntity.self) }
                if !removedShows.isEmpty { try await index.deleteAppEntities(identifiedBy: removedShows, ofType: TVShowSearchResultEntity.self) }
                let changedMovies = movieEntities.filter { indexedMovies[$0.id] != movieSignatures[$0.id] }
                let changedShows = showEntities.filter { indexedShows[$0.id] != showSignatures[$0.id] }
                if !changedMovies.isEmpty { try await index.indexAppEntities(changedMovies) }
                if !changedShows.isEmpty { try await index.indexAppEntities(changedShows) }
                indexedMovies = movieSignatures
                indexedShows = showSignatures
                hasRebuiltIndex = true
            } catch {
                Logger(subsystem: "MediaManager", category: "Spotlight").error("Library indexing failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }
}
#endif

extension MovieSearchResultEntity {
    init?(libraryMovie movie: Movie) {
        guard let id = movie.tmdbId, id > 0 else { return nil }
        self.init(id: id, title: movie.title, year: movie.year, overview: movie.overview, runtime: movie.runtime)
    }
}

extension TVShowSearchResultEntity {
    init?(libraryShow show: TVShow) {
        guard let id = show.tvdbId, id > 0 else { return nil }
        self.init(id: id, title: show.title, year: show.year, overview: show.overview, seasonCount: show.seasonCount, network: show.network)
    }
}

extension View {
    @ViewBuilder
    func mediaSearchEntityAnnotation<Entity: AppEntity>(_ entity: Entity?) -> some View {
        #if os(iOS)
        if #available(iOS 27.0, *), let entity {
            self.appEntityIdentifier(EntityIdentifier(for: entity))
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func mediaEntityAnnotation(movie: Movie) -> some View {
        #if os(iOS)
        if #available(iOS 27.0, *), let entity = MovieSearchResultEntity(libraryMovie: movie) {
            self.appEntityIdentifier(EntityIdentifier(for: entity))
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func mediaEntityAnnotation(show: TVShow) -> some View {
        #if os(iOS)
        if #available(iOS 27.0, *), let entity = TVShowSearchResultEntity(libraryShow: show) {
            self.appEntityIdentifier(EntityIdentifier(for: entity))
        } else { self }
        #else
        self
        #endif
    }
}

extension View {
    @ViewBuilder
    func legacyMediaNavigationBackground() -> some View {
        #if os(iOS)
        if #available(iOS 27.0, *) { self }
        else {
            self.toolbarBackground(ColorPalette.backgroundDark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        #else
        self
        #endif
    }
}
