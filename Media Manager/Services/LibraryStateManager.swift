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
            invalidateCachedIndexes()
        }
    }
    @Published private(set) var tvShows: [TVShow] = [] {
        didSet {
            tvShowsRevision += 1
            invalidateCachedIndexes()
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

    /// Invalidate all cached indexes when data changes
    private func invalidateCachedIndexes() {
        _movieTmdbIds = nil
        _showTvdbIds = nil
        _showNormalizedTitles = nil
        _showKeys = nil
        _showLeetTitles = nil
        _showLeetKeys = nil
        _comingSoonMovies = nil
        _comingSoonShows = nil
        _recentlyAddedMovies = nil
        _recentlyAddedShows = nil
        _sortedMovies = nil
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
        let result = movies.sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
        _recentlyAddedMovies = result
        return result
    }

    /// Recently added shows (sorted by added date)
    var recentlyAddedShows: [TVShow] {
        if let cached = _recentlyAddedShows { return cached }
        let result = tvShows.sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
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

    private init() {}

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

        // First pass: match with digits intact
        if let year = year {
            let key = "\(normalizedName)-\(year)"
            if showKeys.contains(key) {
                return true
            }
        }
        if showNormalizedTitles.contains(normalizedName) {
            return true
        }

        // Second pass: match with leetspeak normalization
        let leetName = normalizeTitleLeetspeak(name)
        if showLeetTitles.contains(leetName) {
            return true
        }
        if let year = year {
            if showLeetKeys.contains("\(leetName)-\(year)") {
                return true
            }
        }

        return false
    }

    /// Check if a show is in the library - uses TVDB ID if available, falls back to name/year
    func isShowInLibrary(tvdbId: Int?, name: String, year: Int?) -> Bool {
        // Prefer TVDB ID matching (most reliable)
        if let tvdbId = tvdbId, showTvdbIds.contains(tvdbId) {
            return true
        }
        // Fallback to name/year matching
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

        // First pass: match with digits intact
        if let year = year {
            if let show = tvShows.first(where: { normalizeTitle($0.title) == normalizedName && $0.year == year }) {
                return show
            }
        }
        if let show = tvShows.first(where: { normalizeTitle($0.title) == normalizedName }) {
            return show
        }

        // Second pass: match with leetspeak normalization
        let leetName = normalizeTitleLeetspeak(name)
        if let year = year {
            if let show = tvShows.first(where: { normalizeTitleLeetspeak($0.title) == leetName && $0.year == year }) {
                return show
            }
        }
        return tvShows.first { normalizeTitleLeetspeak($0.title) == leetName }
    }

    /// Find a TV show - uses TVDB ID if available, falls back to name/year
    func findShow(tvdbId: Int?, name: String, year: Int?) -> TVShow? {
        // Prefer TVDB ID matching (most reliable)
        if let tvdbId = tvdbId, let show = findShow(byTvdbId: tvdbId) {
            return show
        }
        // Fallback to name/year matching
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
        // Prevent rapid refreshes
        if !forceRefresh, let lastRefresh = lastMoviesRefresh,
           Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            return
        }

        guard !isLoadingMovies else { return }
        isLoadingMovies = true

        do {
            movies = try await RadarrService.shared.fetchMovies(forceRefresh: forceRefresh)
            lastMoviesRefresh = Date()
            moviesErrorMessage = nil
        } catch {
            // Keep existing data on error
            moviesErrorMessage = userFacingLoadError(service: "Radarr", error: error)
        }

        isLoadingMovies = false
    }

    /// Load TV shows from Sonarr
    func loadShows(forceRefresh: Bool = false) async {
        // Prevent rapid refreshes
        if !forceRefresh, let lastRefresh = lastShowsRefresh,
           Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            return
        }

        guard !isLoadingShows else { return }
        isLoadingShows = true

        do {
            tvShows = try await SonarrService.shared.fetchShows(forceRefresh: forceRefresh)
            lastShowsRefresh = Date()
            showsErrorMessage = nil
        } catch {
            // Keep existing data on error
            showsErrorMessage = userFacingLoadError(service: "Sonarr", error: error)
        }

        isLoadingShows = false
    }

    /// Load quality profiles from Sonarr (cached for 24 hours)
    func loadQualityProfiles(forceRefresh: Bool = false) async {
        guard !isLoadingProfiles else { return }
        isLoadingProfiles = true

        do {
            qualityProfiles = try await SonarrService.shared.fetchQualityProfiles(forceRefresh: forceRefresh)
            lastProfilesRefresh = Date()
            qualityProfilesErrorMessage = nil
        } catch {
            // Keep existing data on error
            qualityProfilesErrorMessage = userFacingLoadError(service: "Sonarr", error: error)
        }

        isLoadingProfiles = false
    }

    // MARK: - Cache Invalidation

    /// Invalidate movies cache and refresh
    func invalidateMovies() async {
        await RadarrService.shared.invalidateCache()
        lastMoviesRefresh = nil
        await loadMovies(forceRefresh: true)
    }

    /// Invalidate shows cache and refresh
    func invalidateShows() async {
        await SonarrService.shared.invalidateCache()
        lastShowsRefresh = nil
        await loadShows(forceRefresh: true)
    }

    /// Invalidate all caches
    func invalidateAll() async {
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
        movies.append(movie)
    }

    /// Add a show to local state (optimistic update after add)
    func addShowLocally(_ show: TVShow) {
        tvShows.append(show)
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
