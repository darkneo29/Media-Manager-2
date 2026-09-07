import SwiftUI
import Combine

/// Shared state manager for library data (movies and TV shows)
/// Provides a single source of truth across all views to prevent redundant fetches
@MainActor
class LibraryStateManager: ObservableObject {
    static let shared = LibraryStateManager()

    // MARK: - Published State

    @Published private(set) var movies: [Movie] = [] {
        didSet {
            moviesRevision += 1
            invalidateMovieIndexes()
        }
    }
    @Published private(set) var tvShows: [TVShow] = [] {
        didSet {
            tvShowsRevision += 1
            invalidateShowIndexes()
        }
    }
    @Published private(set) var qualityProfiles: [QualityProfile] = []
    @Published private(set) var isLoadingMovies = false
    @Published private(set) var isLoadingShows = false
    @Published private(set) var isLoadingProfiles = false
    @Published private(set) var lastMoviesRefresh: Date?
    @Published private(set) var lastShowsRefresh: Date?
    @Published private(set) var lastProfilesRefresh: Date?
    @Published private(set) var moviesErrorMessage: String?
    @Published private(set) var showsErrorMessage: String?
    @Published private(set) var qualityProfilesErrorMessage: String?
    @Published private(set) var moviesRevision = 0
    @Published private(set) var tvShowsRevision = 0

    // MARK: - Cached Indexes (for O(1) lookups)

    private var _movieTmdbIds: Set<Int>?
    private var _showTvdbIds: Set<Int>?
    private var _showNormalizedTitles: Set<String>?
    private var _showKeys: Set<String>?
    private var _showLeetTitles: Set<String>?
    private var _showLeetKeys: Set<String>?
    private var _comingSoonMovies: [Movie]?
    private var _comingSoonShows: [TVShow]?
    private var _recentlyAddedMovies: [Movie]?
    private var _recentlyAddedShows: [TVShow]?
    private var _sortedMovies: [Movie]?
    private var _sortedShows: [TVShow]?
    private var moviesLoadGeneration: UInt64 = 0
    private var showsLoadGeneration: UInt64 = 0
    private var profilesLoadGeneration: UInt64 = 0

    private func invalidateMovieIndexes() {
        _movieTmdbIds = nil
        _comingSoonMovies = nil
        _recentlyAddedMovies = nil
        _sortedMovies = nil
    }

    private func invalidateShowIndexes() {
        _showTvdbIds = nil
        _showNormalizedTitles = nil
        _showKeys = nil
        _showLeetTitles = nil
        _showLeetKeys = nil
        _comingSoonShows = nil
        _recentlyAddedShows = nil
        _sortedShows = nil
    }

    // MARK: - Computed Properties (with caching)

    /// Set of TMDB IDs for movies in the library (for quick lookup)
    var movieTmdbIds: Set<Int> {
        if let cached = _movieTmdbIds { return cached }
        let result = Set(movies.compactMap { $0.tmdbId })
        _movieTmdbIds = result
        return result
    }

    /// Set of TVDB IDs for shows in the library
    var showTvdbIds: Set<Int> {
        if let cached = _showTvdbIds { return cached }
        let result = Set(tvShows.compactMap { $0.tvdbId })
        _showTvdbIds = result
        return result
    }

    /// Set of normalized titles for shows (for fuzzy matching)
    var showNormalizedTitles: Set<String> {
        if let cached = _showNormalizedTitles { return cached }
        let result = Set(tvShows.map { normalizeTitle($0.title) })
        _showNormalizedTitles = result
        return result
    }

    /// Set of (normalized title, year) keys for shows
    var showKeys: Set<String> {
        if let cached = _showKeys { return cached }
        let result = Set(tvShows.map { "\(normalizeTitle($0.title))-\($0.year)" })
        _showKeys = result
        return result
    }

    /// Set of leetspeak-normalized titles for fallback matching.
    var showLeetTitles: Set<String> {
        if let cached = _showLeetTitles { return cached }
        let result = Set(tvShows.map { normalizeTitleLeetspeak($0.title) })
        _showLeetTitles = result
        return result
    }

    /// Set of (leetspeak-normalized title, year) keys for fallback matching.
    var showLeetKeys: Set<String> {
        if let cached = _showLeetKeys { return cached }
        let result = Set(tvShows.map { "\(normalizeTitleLeetspeak($0.title))-\($0.year)" })
        _showLeetKeys = result
        return result
    }

    /// Coming soon movies (unreleased but monitored)
    var comingSoonMovies: [Movie] {
        if let cached = _comingSoonMovies { return cached }
        let result = movies.filter { $0.isComingSoon && $0.monitored }
        _comingSoonMovies = result
        return result
    }

    /// Coming soon shows (unreleased but monitored)
    var comingSoonShows: [TVShow] {
        if let cached = _comingSoonShows { return cached }
        let result = tvShows.filter { $0.isComingSoon && $0.monitored }
        _comingSoonShows = result
        return result
    }

    /// Recently added movies (sorted by added date)
    var recentlyAddedMovies: [Movie] {
        if let cached = _recentlyAddedMovies { return cached }
        let result = movies.map { (item: $0, date: $0.addedDate ?? .distantPast) }
            .sorted { $0.date > $1.date }.map(\.item)
        _recentlyAddedMovies = result
        return result
    }

    /// Recently added shows (sorted by added date)
    var recentlyAddedShows: [TVShow] {
        if let cached = _recentlyAddedShows { return cached }
        let result = tvShows.map { (item: $0, date: $0.addedDate ?? .distantPast) }
            .sorted { $0.date > $1.date }.map(\.item)
        _recentlyAddedShows = result
        return result
    }

    /// Movies sorted alphabetically by title
    var sortedMovies: [Movie] {
        if let cached = _sortedMovies { return cached }
        let result = movies.sorted { $0.title < $1.title }
        _sortedMovies = result
        return result
    }

    /// TV shows sorted alphabetically by title
    var sortedShows: [TVShow] {
        if let cached = _sortedShows { return cached }
        let result = tvShows.sorted { $0.title < $1.title }
        _sortedShows = result
        return result
    }

    /// Default quality profile (HD preference)
    var defaultQualityProfile: QualityProfile? {
        qualityProfiles.first(where: { $0.name.lowercased().contains("hd") }) ?? qualityProfiles.first
    }

    // MARK: - Refresh Thresholds

    private let refreshThreshold: TimeInterval = 30 // 30 seconds minimum between refreshes

    private let isRadarrConfigured: @MainActor () -> Bool
    private let isSonarrConfigured: @MainActor () -> Bool

    init(
        isRadarrConfigured: @escaping @MainActor () -> Bool = { ConfigurationManager.shared.isRadarrConfigured },
        isSonarrConfigured: @escaping @MainActor () -> Bool = { ConfigurationManager.shared.isSonarrConfigured }
    ) {
        self.isRadarrConfigured = isRadarrConfigured
        self.isSonarrConfigured = isSonarrConfigured
    }

    // MARK: - Library Lookup

    /// Check if a movie is in the library by TMDB ID
    func isMovieInLibrary(tmdbId: Int) -> Bool {
        movieTmdbIds.contains(tmdbId)
    }

    /// Check if a show is in the library by TVDB ID (most reliable)
    func isShowInLibrary(tvdbId: Int) -> Bool {
        showTvdbIds.contains(tvdbId)
    }

    /// Check if a show is in the library (by title/year matching - fallback)
    func isShowInLibrary(name: String, year: Int?) -> Bool {
        let normalizedName = normalizeTitle(name)

        if let year = year, year > 0 {
            return showKeys.contains("\(normalizedName)-\(year)") ||
                showLeetKeys.contains("\(normalizeTitleLeetspeak(name))-\(year)")
        }
        return showNormalizedTitles.contains(normalizedName) ||
            showLeetTitles.contains(normalizeTitleLeetspeak(name))
    }

    /// A known TVDB ID is authoritative; use title matching only without one.
    func isShowInLibrary(tvdbId: Int?, name: String, year: Int?) -> Bool {
        if let tvdbId, tvdbId > 0 {
            return showTvdbIds.contains(tvdbId)
        }
        return isShowInLibrary(name: name, year: year)
    }

    /// Find a movie in the library by TMDB ID
    func findMovie(byTmdbId tmdbId: Int) -> Movie? {
        movies.first { $0.tmdbId == tmdbId }
    }

    /// Find a TV show in the library by TVDB ID (most reliable)
    func findShow(byTvdbId tvdbId: Int) -> TVShow? {
        tvShows.first { $0.tvdbId == tvdbId }
    }

    /// Find a TV show in the library by name and year
    func findShow(byName name: String, year: Int?) -> TVShow? {
        let normalizedName = normalizeTitle(name)

        let candidates = tvShows.filter { show in
            guard let year, year > 0 else { return true }
            return show.year == year
        }
        if let show = candidates.first(where: { normalizeTitle($0.title) == normalizedName }) {
            return show
        }
        let leetName = normalizeTitleLeetspeak(name)
        return candidates.first { normalizeTitleLeetspeak($0.title) == leetName }
    }

    /// A known TVDB ID is authoritative; use title matching only without one.
    func findShow(tvdbId: Int?, name: String, year: Int?) -> TVShow? {
        if let tvdbId, tvdbId > 0 {
            return findShow(byTvdbId: tvdbId)
        }
        return findShow(byName: name, year: year)
    }

    /// Normalize a title for comparison (digits intact, no leetspeak)
    private func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Normalize a title with leetspeak replacement (secondary matching strategy)
    private func normalizeTitleLeetspeak(_ title: String) -> String {
        var normalized = normalizeTitle(title)

        let leetReplacements: [(String, String)] = [
            ("0", "o"), ("1", "i"), ("3", "e"), ("4", "a"),
            ("5", "s"), ("7", "t"), ("8", "b"), ("@", "a"), ("$", "s")
        ]

        for (leet, letter) in leetReplacements {
            normalized = normalized.replacingOccurrences(of: leet, with: letter)
        }

        return normalized
    }

    // MARK: - Data Loading

    /// Load all library data (movies, shows, quality profiles)
    func loadAll(forceRefresh: Bool = false) async {
        async let moviesTask: () = loadMovies(forceRefresh: forceRefresh)
        async let showsTask: () = loadShows(forceRefresh: forceRefresh)
        async let profilesTask: () = loadQualityProfiles(forceRefresh: forceRefresh)

        _ = await (moviesTask, showsTask, profilesTask)
    }

    /// Load movies from Radarr
    func loadMovies(forceRefresh: Bool = false) async {
        guard isRadarrConfigured() else {
            resetMovies()
            return
        }
        // Prevent rapid refreshes
        if !forceRefresh, let lastRefresh = lastMoviesRefresh,
           Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            return
        }

        guard forceRefresh || !isLoadingMovies else { return }
        moviesLoadGeneration &+= 1
        let loadGeneration = moviesLoadGeneration
        isLoadingMovies = true

        do {
            let fetchedMovies = try await RadarrService.shared.fetchMovies(forceRefresh: forceRefresh)
            guard loadGeneration == moviesLoadGeneration else { return }
            movies = fetchedMovies
            lastMoviesRefresh = Date()
            moviesErrorMessage = nil
        } catch {
            guard loadGeneration == moviesLoadGeneration else { return }
            // Keep existing data on error
            moviesErrorMessage = userFacingLoadError(service: "Radarr", error: error)
        }

        if loadGeneration == moviesLoadGeneration {
            isLoadingMovies = false
        }
    }

    /// Load TV shows from Sonarr
    func loadShows(forceRefresh: Bool = false) async {
        guard isSonarrConfigured() else {
            resetShows()
            return
        }
        // Prevent rapid refreshes
        if !forceRefresh, let lastRefresh = lastShowsRefresh,
           Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            return
        }

        guard forceRefresh || !isLoadingShows else { return }
        showsLoadGeneration &+= 1
        let loadGeneration = showsLoadGeneration
        isLoadingShows = true

        do {
            let fetchedShows = try await SonarrService.shared.fetchShows(forceRefresh: forceRefresh)
            guard loadGeneration == showsLoadGeneration else { return }
            tvShows = fetchedShows
            lastShowsRefresh = Date()
            showsErrorMessage = nil
        } catch {
            guard loadGeneration == showsLoadGeneration else { return }
            // Keep existing data on error
            showsErrorMessage = userFacingLoadError(service: "Sonarr", error: error)
        }

        if loadGeneration == showsLoadGeneration {
            isLoadingShows = false
        }
    }

    /// Load quality profiles from Sonarr (cached for 24 hours)
    func loadQualityProfiles(forceRefresh: Bool = false) async {
        guard isSonarrConfigured() else {
            resetProfiles()
            return
        }
        guard forceRefresh || !isLoadingProfiles else { return }
        profilesLoadGeneration &+= 1
        let loadGeneration = profilesLoadGeneration
        isLoadingProfiles = true

        do {
            let fetchedProfiles = try await SonarrService.shared.fetchQualityProfiles(forceRefresh: forceRefresh)
            guard loadGeneration == profilesLoadGeneration else { return }
            qualityProfiles = fetchedProfiles
            lastProfilesRefresh = Date()
            qualityProfilesErrorMessage = nil
        } catch {
            guard loadGeneration == profilesLoadGeneration else { return }
            // Keep existing data on error
            qualityProfilesErrorMessage = userFacingLoadError(service: "Sonarr", error: error)
        }

        if loadGeneration == profilesLoadGeneration {
            isLoadingProfiles = false
        }
    }

    private func resetMovies() {
        moviesLoadGeneration &+= 1
        if !movies.isEmpty { movies = [] }
        lastMoviesRefresh = nil
        moviesErrorMessage = nil
        isLoadingMovies = false
    }

    private func resetShows() {
        showsLoadGeneration &+= 1
        if !tvShows.isEmpty { tvShows = [] }
        lastShowsRefresh = nil
        showsErrorMessage = nil
        isLoadingShows = false
    }

    private func resetProfiles() {
        profilesLoadGeneration &+= 1
        qualityProfiles = []
        lastProfilesRefresh = nil
        qualityProfilesErrorMessage = nil
        isLoadingProfiles = false
    }

    // MARK: - Cache Invalidation

    /// Invalidate movies cache and refresh
    func invalidateMovies() async {
        resetMovies()
        await RadarrService.shared.invalidateCache()
        lastMoviesRefresh = nil
        await loadMovies(forceRefresh: true)
    }

    /// Invalidate shows cache and refresh
    func invalidateShows() async {
        resetShows()
        resetProfiles()
        await SonarrService.shared.invalidateCache()
        lastShowsRefresh = nil
        async let shows: () = loadShows(forceRefresh: true)
        async let profiles: () = loadQualityProfiles(forceRefresh: true)
        _ = await (shows, profiles)
    }

    /// Invalidate all caches
    func invalidateAll() async {
        resetMovies()
        resetShows()
        resetProfiles()
        await RadarrService.shared.invalidateCache()
        await SonarrService.shared.invalidateCache()
        await TMDBService.shared.invalidateCache()
        lastMoviesRefresh = nil
        lastShowsRefresh = nil
        lastProfilesRefresh = nil
        await loadAll(forceRefresh: true)
    }

    // MARK: - Optimistic Updates

    /// Add a movie to local state (optimistic update after add)
    func addMovieLocally(_ movie: Movie) {
        if let index = movies.firstIndex(where: { $0.id == movie.id }) {
            movies[index] = movie
        } else {
            movies.append(movie)
        }
    }

    /// Add a show to local state (optimistic update after add)
    func addShowLocally(_ show: TVShow) {
        if let index = tvShows.firstIndex(where: { $0.id == show.id }) {
            tvShows[index] = show
        } else {
            tvShows.append(show)
        }
    }

    /// Replace an existing movie with fresh server state.
    func updateMovieLocally(_ movie: Movie) {
        addMovieLocally(movie)
    }

    /// Replace an existing series with fresh server state.
    func updateShowLocally(_ show: TVShow) {
        addShowLocally(show)
    }

    /// Remove a movie from local state
    func removeMovieLocally(id: Int) {
        movies.removeAll { $0.id == id }
    }

    /// Remove a show from local state
    func removeShowLocally(id: Int) {
        tvShows.removeAll { $0.id == id }
    }

    private func userFacingLoadError(service: String, error: Error) -> String {
        let message = error.localizedDescription
        if message.isEmpty {
            return "Could not reach \(service). Check your server URL, API key, and network connection."
        }
        return "\(service): \(message)"
    }
}
