import Foundation

class TMDBService {
    static let shared = TMDBService()

    private let baseURL = "https://api.themoviedb.org/3"
    private let config = ConfigurationManager.shared
    private let maxTVDBEnrichmentPerRequest = 8

    private actor TVExternalIdCache {
        private var knownTVDBIds: [Int: Int] = [:]
        private var knownMissingTMDBIds: Set<Int> = []

        func tvdbId(for tmdbId: Int) -> Int? {
            knownTVDBIds[tmdbId]
        }

        func isKnownMissing(_ tmdbId: Int) -> Bool {
            knownMissingTMDBIds.contains(tmdbId)
        }

        func store(tvdbId: Int?, for tmdbId: Int) {
            if let tvdbId {
                knownTVDBIds[tmdbId] = tvdbId
                knownMissingTMDBIds.remove(tmdbId)
            } else {
                knownTVDBIds.removeValue(forKey: tmdbId)
                knownMissingTMDBIds.insert(tmdbId)
            }
        }

        func clear() {
            knownTVDBIds.removeAll()
            knownMissingTMDBIds.removeAll()
        }
    }

    private let externalIdCache = TVExternalIdCache()

    private var accessToken: String {
        config.tmdbAccessToken
    }

    private init() {}

    // MARK: - Trending Movies (Cached)

    /// Fetch trending movies for the specified time window
    /// Results are cached for 1 hour
    /// - Parameter timeWindow: "day" or "week" (default: "week")
    /// - Parameter forceRefresh: If true, bypasses cache
    func fetchTrendingMovies(timeWindow: String = "week", forceRefresh: Bool = false) async throws -> [TrendingMovie] {
        let cacheKey = CacheManager.CacheKey.tmdbTrendingMovies

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchTrendingMoviesFromAPI(timeWindow: timeWindow)
        }
    }

    /// Direct API call for trending movies
    private func fetchTrendingMoviesFromAPI(timeWindow: String) async throws -> [TrendingMovie] {
        guard let url = URL(string: "\(baseURL)/trending/movie/\(timeWindow)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBPagedResponse<TrendingMovie>.self, from: data)
        return decoded.results
    }

    // MARK: - Trending TV Shows (Cached)

    /// Fetch trending TV shows for the specified time window
    /// Results are cached for 1 hour
    /// - Parameter timeWindow: "day" or "week" (default: "week")
    /// - Parameter forceRefresh: If true, bypasses cache
    func fetchTrendingTVShows(timeWindow: String = "week", forceRefresh: Bool = false) async throws -> [TrendingTVShow] {
        let cacheKey = CacheManager.CacheKey.tmdbTrendingTVShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchTrendingTVShowsFromAPI(timeWindow: timeWindow)
        }
    }

    /// Direct API call for trending TV shows
    private func fetchTrendingTVShowsFromAPI(timeWindow: String) async throws -> [TrendingTVShow] {
        guard let url = URL(string: "\(baseURL)/trending/tv/\(timeWindow)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBPagedResponse<TrendingTVShow>.self, from: data)
        return await enrichTVShowsWithTVDBIDs(decoded.results)
    }

    // MARK: - Discover: Popular Movies (Cached)

    func fetchPopularMovies(forceRefresh: Bool = false) async throws -> [TrendingMovie] {
        let cacheKey = CacheManager.CacheKey.tmdbPopularMovies

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchMovieList(endpoint: "movie/popular")
        }
    }

    // MARK: - Discover: Top Rated Movies (Cached)

    func fetchTopRatedMovies(forceRefresh: Bool = false) async throws -> [TrendingMovie] {
        let cacheKey = CacheManager.CacheKey.tmdbTopRatedMovies

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchMovieList(endpoint: "movie/top_rated")
        }
    }

    // MARK: - Discover: Now Playing Movies (Cached)

    func fetchNowPlayingMovies(forceRefresh: Bool = false) async throws -> [TrendingMovie] {
        let cacheKey = CacheManager.CacheKey.tmdbNowPlayingMovies

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.nowPlaying
        ) {
            try await self.fetchMovieList(endpoint: "movie/now_playing")
        }
    }

    // MARK: - Discover: Upcoming Movies (Cached)

    func fetchUpcomingMovies(forceRefresh: Bool = false) async throws -> [TrendingMovie] {
        let cacheKey = CacheManager.CacheKey.tmdbUpcomingMovies

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.upcoming
        ) {
            try await self.fetchMovieList(endpoint: "movie/upcoming")
        }
    }

    // MARK: - Discover: Popular TV Shows (Cached)

    func fetchPopularTVShows(forceRefresh: Bool = false) async throws -> [TrendingTVShow] {
        let cacheKey = CacheManager.CacheKey.tmdbPopularTVShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchTVShowList(endpoint: "tv/popular")
        }
    }

    // MARK: - Discover: Top Rated TV Shows (Cached)

    func fetchTopRatedTVShows(forceRefresh: Bool = false) async throws -> [TrendingTVShow] {
        let cacheKey = CacheManager.CacheKey.tmdbTopRatedTVShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.trending
        ) {
            try await self.fetchTVShowList(endpoint: "tv/top_rated")
        }
    }

    // MARK: - Discover: On The Air TV Shows (Cached)

    func fetchOnTheAirTVShows(forceRefresh: Bool = false) async throws -> [TrendingTVShow] {
        let cacheKey = CacheManager.CacheKey.tmdbOnTheAirTVShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.nowPlaying
        ) {
            try await self.fetchTVShowList(endpoint: "tv/on_the_air")
        }
    }

    // MARK: - Discover: Airing Today TV Shows (Cached)

    func fetchAiringTodayTVShows(forceRefresh: Bool = false) async throws -> [TrendingTVShow] {
        let cacheKey = CacheManager.CacheKey.tmdbAiringTodayTVShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.airingToday
        ) {
            try await self.fetchTVShowList(endpoint: "tv/airing_today")
        }
    }

    // MARK: - Generic Fetch Helpers

    /// Generic movie list fetch (works for popular, top_rated, now_playing, upcoming)
    private func fetchMovieList(endpoint: String) async throws -> [TrendingMovie] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBPagedResponse<TrendingMovie>.self, from: data)
        return decoded.results
    }

    /// Generic TV show list fetch with TVDB ID enrichment
    private func fetchTVShowList(endpoint: String) async throws -> [TrendingTVShow] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBPagedResponse<TrendingTVShow>.self, from: data)
        return await enrichTVShowsWithTVDBIDs(decoded.results)
    }

    /// Adds TVDB IDs to TV show results using a bounded/cached enrichment strategy.
    private func enrichTVShowsWithTVDBIDs(_ shows: [TrendingTVShow]) async -> [TrendingTVShow] {
        guard !shows.isEmpty else { return shows }

        var enriched = shows
        var uncachedIndexes: [Int] = []
        uncachedIndexes.reserveCapacity(shows.count)

        for index in enriched.indices {
            let tmdbId = enriched[index].id
            if let cachedTVDBId = await externalIdCache.tvdbId(for: tmdbId) {
                enriched[index].tvdbId = cachedTVDBId
            } else if !(await externalIdCache.isKnownMissing(tmdbId)) {
                uncachedIndexes.append(index)
            }
        }

        guard !uncachedIndexes.isEmpty else { return enriched }

        let indexesToFetch = Array(uncachedIndexes.prefix(maxTVDBEnrichmentPerRequest))
        await withTaskGroup(of: (Int, Int?).self) { group in
            for index in indexesToFetch {
                let tmdbId = enriched[index].id
                group.addTask {
                    do {
                        let externalIds = try await self.fetchTVShowExternalIds(tmdbId: tmdbId)
                        await self.externalIdCache.store(tvdbId: externalIds.tvdbId, for: tmdbId)
                        return (index, externalIds.tvdbId)
                    } catch {
                        return (index, nil)
                    }
                }
            }

            for await (index, tvdbId) in group {
                if let tvdbId {
                    enriched[index].tvdbId = tvdbId
                }
            }
        }

        return enriched
    }

    // MARK: - Search Movies

    /// Search for movies by query string
    /// - Parameter query: The search query (movie title)
    /// - Returns: Array of TrendingMovie results from TMDB search
    func searchMovies(query: String) async throws -> [TrendingMovie] {
        var components = URLComponents(string: "\(baseURL)/search/movie")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBPagedResponse<TrendingMovie>.self, from: data)
        return decoded.results
    }

    // MARK: - Image URLs

    /// Generate full poster URL for TMDB image path
    /// - Parameters:
    ///   - path: The poster path from API (e.g., "/abc123.jpg")
    ///   - size: Image size (default: "w342"). Options: w92, w154, w185, w342, w500, w780, original
    ///   Note: Using w342 as default for better bandwidth optimization while maintaining quality
    func posterURL(path: String?, size: String = "w342") -> URL? {
        guard let path = path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// Generate full backdrop URL for TMDB image path
    /// - Parameters:
    ///   - path: The backdrop path from API (e.g., "/abc123.jpg")
    ///   - size: Image size (default: "w780"). Options: w300, w780, w1280, original
    func backdropURL(path: String?, size: String = "w780") -> URL? {
        guard let path = path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - Connection Test

    /// Test connection to TMDB API with the provided or stored access token
    /// - Parameter token: Optional token to test (uses stored token if nil)
    func testConnection(token: String? = nil) async throws {
        let testToken = token ?? accessToken

        guard let url = URL(string: "\(baseURL)/authentication") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(testToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Invalidate all TMDB-related caches
    func invalidateCache() async {
        await CacheManager.shared.clearWithPrefix("tmdb.")
        await externalIdCache.clear()
    }

    // MARK: - Video/Trailer Methods

    /// Fetch videos for a movie by TMDB ID
    /// - Parameter tmdbId: The TMDB ID of the movie
    /// - Returns: Array of TMDBVideo objects
    func fetchMovieVideos(tmdbId: Int) async throws -> [TMDBVideo] {
        guard let url = URL(string: "\(baseURL)/movie/\(tmdbId)/videos") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
        return decoded.results
    }

    /// Fetch videos for a TV show by TMDB ID
    /// - Parameter tmdbId: The TMDB ID of the TV show
    /// - Returns: Array of TMDBVideo objects
    func fetchTVShowVideos(tmdbId: Int) async throws -> [TMDBVideo] {
        guard let url = URL(string: "\(baseURL)/tv/\(tmdbId)/videos") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
        return decoded.results
    }

    /// Fetch external IDs for a TV show (including TVDB ID)
    /// - Parameter tmdbId: The TMDB ID of the TV show
    /// - Returns: TMDBExternalIds containing tvdb_id and other external IDs
    func fetchTVShowExternalIds(tmdbId: Int) async throws -> TMDBExternalIds {
        guard let url = URL(string: "\(baseURL)/tv/\(tmdbId)/external_ids") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(TMDBExternalIds.self, from: data)
    }

    /// Find TMDB ID for a TV show using its TVDB ID
    /// - Parameter tvdbId: The TVDB ID of the show
    /// - Returns: The TMDB ID if found, nil otherwise
    func findTMDBIdByTVDBId(tvdbId: Int) async throws -> Int? {
        guard let url = URL(string: "\(baseURL)/find/\(tvdbId)?external_source=tvdb_id") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TMDBFindResponse.self, from: data)
        return decoded.tvResults.first?.id
    }

    /// Get the best trailer URL for a movie
    /// Prioritizes: Official Trailers > Any Trailer > Any YouTube video
    /// - Parameter tmdbId: The TMDB ID of the movie
    /// - Returns: YouTube URL for the trailer, or nil if not found
    func getMovieTrailerURL(tmdbId: Int) async -> URL? {
        do {
            let videos = try await fetchMovieVideos(tmdbId: tmdbId)
            return selectBestTrailer(from: videos)
        } catch {
            #if DEBUG
            print("Error fetching movie trailer: \(error)")
            #endif
            return nil
        }
    }

    /// Get the best trailer URL for a TV show
    /// Prioritizes: Official Trailers > Any Trailer > Any YouTube video
    /// - Parameter tvdbId: The TVDB ID of the show (will be converted to TMDB ID)
    /// - Returns: YouTube URL for the trailer, or nil if not found
    func getTVShowTrailerURL(tvdbId: Int) async -> URL? {
        do {
            // First, find the TMDB ID from TVDB ID
            guard let tmdbId = try await findTMDBIdByTVDBId(tvdbId: tvdbId) else {
                #if DEBUG
                print("Could not find TMDB ID for TVDB ID: \(tvdbId)")
                #endif
                return nil
            }

            let videos = try await fetchTVShowVideos(tmdbId: tmdbId)
            return selectBestTrailer(from: videos)
        } catch {
            #if DEBUG
            print("Error fetching TV show trailer: \(error)")
            #endif
            return nil
        }
    }

    /// Get the best trailer URL for a TV show using TMDB ID directly
    /// Prioritizes: Official Trailers > Any Trailer > Any YouTube video
    /// - Parameter tmdbId: The TMDB ID of the TV show
    /// - Returns: YouTube URL for the trailer, or nil if not found
    func getTVShowTrailerURLByTMDBId(tmdbId: Int) async -> URL? {
        do {
            let videos = try await fetchTVShowVideos(tmdbId: tmdbId)
            return selectBestTrailer(from: videos)
        } catch {
            #if DEBUG
            print("Error fetching TV show trailer: \(error)")
            #endif
            return nil
        }
    }

    /// Select the best trailer from a list of videos
    /// Priority: Official Trailer > Any Trailer > Any YouTube video
    private func selectBestTrailer(from videos: [TMDBVideo]) -> URL? {
        // Filter to YouTube videos only
        let youtubeVideos = videos.filter { $0.site.lowercased() == "youtube" }

        // Priority 1: Official trailer
        if let officialTrailer = youtubeVideos.first(where: { $0.isTrailer && $0.isOfficial }) {
            return officialTrailer.youtubeURL
        }

        // Priority 2: Any trailer
        if let anyTrailer = youtubeVideos.first(where: { $0.isTrailer }) {
            return anyTrailer.youtubeURL
        }

        // Priority 3: Any YouTube video (teaser, featurette, etc.)
        if let anyVideo = youtubeVideos.first {
            return anyVideo.youtubeURL
        }

        return nil
    }
}
