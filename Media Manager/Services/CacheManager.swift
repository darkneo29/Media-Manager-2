import Foundation

/// Thread-safe generic cache with TTL (Time To Live) support
/// Used for caching API responses to reduce network calls
actor CacheManager {
    static let shared = CacheManager()

    // MARK: - Cache Entry

    private struct CacheEntry<T> {
        let data: T
        let timestamp: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    // MARK: - TTL Constants

    struct TTL {
        /// Quality profiles rarely change - cache for 24 hours
        static let qualityProfiles: TimeInterval = 24 * 60 * 60

        /// Library data (movies/shows) - cache for 5 minutes
        static let library: TimeInterval = 5 * 60

        /// Trending content - cache for 1 hour
        static let trending: TimeInterval = 60 * 60

        /// Now playing / on the air - cache for 30 minutes
        static let nowPlaying: TimeInterval = 30 * 60

        /// Upcoming movies - cache for 6 hours
        static let upcoming: TimeInterval = 6 * 60 * 60

        /// Airing today - cache for 12 hours
        static let airingToday: TimeInterval = 12 * 60 * 60

        /// Search results - cache for 15 minutes
        static let search: TimeInterval = 15 * 60

        /// Short-lived cache for frequently changing data
        static let short: TimeInterval = 60
    }

    // MARK: - Storage

    private var cache: [String: Any] = [:]
    private var timestamps: [String: (date: Date, ttl: TimeInterval)] = [:]
    private struct InFlightRequest {
        let id: UUID
        let epoch: UInt64
        let generation: UInt64
        let task: Task<Any, Error>
    }

    private var inFlightRequests: [String: InFlightRequest] = [:]
    private var requestGenerations: [String: UInt64] = [:]
    private var epoch: UInt64 = 0

    private init() {}

    // MARK: - Cache Operations

    /// Get cached data if available and not expired
    func get<T>(_ key: String) -> T? {
        guard let entry = cache[key] as? CacheEntry<T> else {
            return nil
        }

        if entry.isExpired {
            cache.removeValue(forKey: key)
            timestamps.removeValue(forKey: key)
            return nil
        }

        return entry.data
    }

    /// Store data in cache with TTL
    func set<T>(_ key: String, data: T, ttl: TimeInterval) {
        let entry = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
        cache[key] = entry
        timestamps[key] = (date: Date(), ttl: ttl)
    }

    /// Remove specific cache entry
    func remove(_ key: String) {
        invalidateGeneration(for: key)
        cache.removeValue(forKey: key)
        timestamps.removeValue(forKey: key)
        inFlightRequests.removeValue(forKey: key)?.task.cancel()
    }

    /// Clear all cache entries
    func clearAll() {
        epoch &+= 1
        requestGenerations.removeAll()
        cache.removeAll()
        timestamps.removeAll()
        inFlightRequests.values.forEach { $0.task.cancel() }
        inFlightRequests.removeAll()
    }

    /// Clear all entries matching a prefix
    func clearWithPrefix(_ prefix: String) {
        let keysToRemove = Set(cache.keys.filter { $0.hasPrefix(prefix) })
            .union(timestamps.keys.filter { $0.hasPrefix(prefix) })
            .union(inFlightRequests.keys.filter { $0.hasPrefix(prefix) })
            .union(requestGenerations.keys.filter { $0.hasPrefix(prefix) })
        for key in keysToRemove {
            invalidateGeneration(for: key)
            cache.removeValue(forKey: key)
            timestamps.removeValue(forKey: key)
            inFlightRequests.removeValue(forKey: key)?.task.cancel()
        }
    }

    /// Check if cache contains valid (non-expired) entry
    func contains(_ key: String) -> Bool {
        guard let info = timestamps[key] else {
            return false
        }
        let isExpired = Date().timeIntervalSince(info.date) > info.ttl
        if isExpired {
            cache.removeValue(forKey: key)
            timestamps.removeValue(forKey: key)
            return false
        }
        return true
    }

    // MARK: - Request Deduplication

    /// Execute a fetch with caching and request deduplication
    /// If the same key is being fetched, waits for the existing request instead of making a duplicate
    func fetchWithCache<T>(
        key: String,
        ttl: TimeInterval,
        bypassInFlight: Bool = false,
        fetch: @escaping () async throws -> T
    ) async throws -> T {
        // Check cache first
        if let cached: T = get(key) {
            return cached
        }

        // Check for in-flight request
        if bypassInFlight {
            invalidateGeneration(for: key)
            inFlightRequests[key]?.task.cancel()
            inFlightRequests.removeValue(forKey: key)
        } else if let existingRequest = inFlightRequests[key] {
            return try await resolvedValue(from: existingRequest, for: key)
        }

        // Create new request
        let requestID = UUID()
        let requestGeneration = nextGeneration(for: key)
        let requestEpoch = epoch
        let task = Task<Any, Error> {
            let result = try await fetch()
            return result as Any
        }

        let inFlightRequest = InFlightRequest(
            id: requestID,
            epoch: requestEpoch,
            generation: requestGeneration,
            task: task
        )
        inFlightRequests[key] = inFlightRequest

        do {
            let result = try await task.value

            // A force refresh or invalidation may have superseded this request
            // while its fetch ignored/delayed cancellation. Never let an older
            // request remove or cache over the replacement.
            guard isCurrent(inFlightRequest, for: key),
                  inFlightRequests[key]?.id == requestID else {
                return try await resultFromReplacement(for: key)
            }

            inFlightRequests.removeValue(forKey: key)

            if let typedResult = result as? T {
                // Cache the result
                set(key, data: typedResult, ttl: ttl)
                return typedResult
            }

            throw CacheError.typeMismatch
        } catch {
            guard isCurrent(inFlightRequest, for: key),
                  inFlightRequests[key]?.id == requestID else {
                return try await resultFromReplacement(for: key)
            }
            inFlightRequests.removeValue(forKey: key)
            throw error
        }
    }

    /// Returns the newest value after a request was superseded. This prevents
    /// callers awaiting an older request from observing stale data.
    private func resultFromReplacement<T>(for key: String) async throws -> T {
        if let cached: T = get(key) {
            return cached
        }

        guard let replacement = inFlightRequests[key] else {
            throw CancellationError()
        }

        return try await resolvedValue(from: replacement, for: key)
    }

    private func resolvedValue<T>(from request: InFlightRequest, for key: String) async throws -> T {
        do {
            let result = try await request.task.value
            guard isCurrent(request, for: key) else {
                return try await resultFromReplacement(for: key)
            }
            guard let typedResult = result as? T else {
                throw CacheError.typeMismatch
            }
            return typedResult
        } catch {
            guard isCurrent(request, for: key) else {
                return try await resultFromReplacement(for: key)
            }
            throw error
        }
    }

    private func nextGeneration(for key: String) -> UInt64 {
        let next = (requestGenerations[key] ?? 0) &+ 1
        requestGenerations[key] = next
        return next
    }

    private func invalidateGeneration(for key: String) {
        requestGenerations[key] = (requestGenerations[key] ?? 0) &+ 1
    }

    private func isCurrent(_ request: InFlightRequest, for key: String) -> Bool {
        request.epoch == epoch && request.generation == requestGenerations[key]
    }

    // MARK: - Cache Keys

    enum CacheKey {
        // Radarr
        static let radarrMovies = "radarr.movies"
        static let radarrQualityProfiles = "radarr.qualityProfiles"
        static let radarrRootFolders = "radarr.rootFolders"
        static let radarrTags = "radarr.tags"
        static let radarrQueue = "radarr.queue"
        static func radarrSearch(_ term: String) -> String { "radarr.search.\(term.lowercased())" }
        static func movieFiles(_ movieId: Int) -> String { "radarr.moviefiles.\(movieId)" }

        // Sonarr
        static let sonarrShows = "sonarr.shows"
        static let sonarrQualityProfiles = "sonarr.qualityProfiles"
        static let sonarrRootFolders = "sonarr.rootFolders"
        static let sonarrTags = "sonarr.tags"
        static let sonarrQueue = "sonarr.queue"
        static let sonarrWanted = "sonarr.wanted"
        static func sonarrSearch(_ term: String) -> String { "sonarr.search.\(term.lowercased())" }
        static func episodeFiles(_ seriesId: Int) -> String { "sonarr.episodefiles.\(seriesId)" }
        static func episodes(_ seriesId: Int) -> String { "sonarr.episodes.\(seriesId)" }

        // TMDB
        static func tmdbTrendingMovies(timeWindow: String) -> String {
            "tmdb.trending.movies.\(timeWindow.lowercased())"
        }
        static func tmdbTrendingTVShows(timeWindow: String) -> String {
            "tmdb.trending.tvshows.\(timeWindow.lowercased())"
        }
        static let tmdbPopularMovies = "tmdb.popular.movies"
        static let tmdbTopRatedMovies = "tmdb.toprated.movies"
        static let tmdbNowPlayingMovies = "tmdb.nowplaying.movies"
        static let tmdbUpcomingMovies = "tmdb.upcoming.movies"
        static let tmdbPopularTVShows = "tmdb.popular.tvshows"
        static let tmdbTopRatedTVShows = "tmdb.toprated.tvshows"
        static let tmdbOnTheAirTVShows = "tmdb.ontheair.tvshows"
        static let tmdbAiringTodayTVShows = "tmdb.airingtoday.tvshows"
    }
}

// MARK: - Errors

enum CacheError: Error {
    case typeMismatch
    case notFound
}
