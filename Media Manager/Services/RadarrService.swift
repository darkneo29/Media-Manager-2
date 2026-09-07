import Foundation

// MARK: - Radarr Error Types

enum RadarrError: LocalizedError {
    case apiError(String)
    case movieAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return message
        case .movieAlreadyExists(let title):
            return "\(title) is already in your library"
        }
    }
}

struct RadarrErrorResponse: Codable {
    let propertyName: String?
    let errorMessage: String
    let attemptedValue: String?
    let severity: String?
}

class RadarrService {
    static let shared = RadarrService()

    private let config = ConfigurationManager.shared

    private var baseURL: String {
        config.radarrBaseURL
    }

    private var serverURL: String {
        config.radarrURL
    }

    private var apiKey: String {
        config.radarrAPIKey
    }

    private init() {}

    // MARK: - Request Helpers

    /// Creates an authenticated URLRequest with API key header and timeout
    private func authenticatedRequest(url: URL, apiKey: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(apiKey ?? self.apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    /// Generates a proper title slug for Radarr
    private func generateTitleSlug(_ title: String, id: Int) -> String {
        var slug = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        // Strip non-alphanumeric except hyphens
        slug = slug.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        // Collapse multiple hyphens
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        // Trim leading/trailing hyphens
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(slug)-\(id)"
    }

    /// Converts a relative image path from Radarr to a full URL
    func imageURL(for relativePath: String) -> URL? {
        ServerImageURL.resolve(relativePath, serverURL: serverURL)
    }

    /// Fetches image data with proper authentication
    func fetchImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if ServerImageURL.matchesServer(url, serverURL: serverURL) {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    // MARK: - Cached Methods

    /// Fetches movies with caching support
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    func fetchMovies(forceRefresh: Bool = false) async throws -> [Movie] {
        let cacheKey = CacheManager.CacheKey.radarrMovies

        // Clear cache if force refresh requested
        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.library,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchMoviesFromAPI()
        }
    }

    /// Direct API call for movies (used internally and for cache population)
    private func fetchMoviesFromAPI() async throws -> [Movie] {
        guard let url = URL(string: "\(baseURL)/movie") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let movies = try JSONDecoder().decode([Movie].self, from: data)
        return movies
    }

    /// Search movies with caching (search results cached for 15 minutes)
    func searchMovies(term: String) async throws -> [MovieLookup] {
        let cacheKey = CacheManager.CacheKey.radarrSearch(term)

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.search
        ) {
            try await self.searchMoviesFromAPI(term: term)
        }
    }

    /// Direct API call for search
    private func searchMoviesFromAPI(term: String) async throws -> [MovieLookup] {
        var components = URLComponents(string: "\(baseURL)/movie/lookup")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term)
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let movies = try JSONDecoder().decode([MovieLookup].self, from: data)
        return movies
    }

    @discardableResult
    func addMovie(
        movie: MovieLookup,
        qualityProfileId: Int = 1,
        rootFolderPath: String = "/movies/",
        minimumAvailability: RadarrMinimumAvailability = .released,
        monitored: Bool = true,
        monitorOption: RadarrMonitorOption = .movieOnly,
        searchForMovie: Bool = true,
        tagIds: [Int] = []
    ) async throws -> Movie {
        guard let url = URL(string: "\(baseURL)/movie") else {
            throw URLError(.badURL)
        }

        // Radarr requires specific payload structure for adding a movie
        let payload: [String: Any] = [
            "title": movie.title,
            "qualityProfileId": qualityProfileId,
            "titleSlug": generateTitleSlug(movie.title, id: movie.tmdbId),
            "images": [], // Simplify for now
            "banner": "",
            "tmdbId": movie.tmdbId,
            "year": movie.year,
            "rootFolderPath": rootFolderPath,
            "minimumAvailability": minimumAvailability.rawValue,
            "monitored": monitored,
            "tags": tagIds,
            "addOptions": [
                "addMethod": "manual",
                "monitor": monitorOption.rawValue,
                "searchForMovie": searchForMovie
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse Radarr's error response for a better message
            if let errorResponse = try? JSONDecoder().decode([RadarrErrorResponse].self, from: data),
               let firstError = errorResponse.first {
                // Check for "already exists" type errors
                if firstError.errorMessage.lowercased().contains("already") ||
                   firstError.errorMessage.lowercased().contains("exists") {
                    throw RadarrError.movieAlreadyExists(movie.title)
                }
                throw RadarrError.apiError(firstError.errorMessage)
            }
            throw URLError(.badServerResponse)
        }

        // Invalidate movies cache after adding
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)

        // Parse and return the added movie
        let addedMovie = try JSONDecoder().decode(Movie.self, from: data)
        return addedMovie
    }

    func deleteMovie(id: Int, deleteFiles: Bool = true, addImportExclusion: Bool = false) async throws {
        guard let url = URL(string: "\(baseURL)/movie/\(id)?deleteFiles=\(deleteFiles)&addImportExclusion=\(addImportExclusion)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate movies cache after deletion
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    func updateMovieMonitoring(movieId: Int, monitored: Bool) async throws {
        guard let getURL = URL(string: "\(baseURL)/movie/\(movieId)") else {
            throw URLError(.badURL)
        }

        let getRequest = authenticatedRequest(url: getURL)
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        guard let httpGetResponse = getResponse as? HTTPURLResponse,
              (200...299).contains(httpGetResponse.statusCode),
              var movieDict = try JSONSerialization.jsonObject(with: getData) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        movieDict["monitored"] = monitored
        let jsonData = try JSONSerialization.data(withJSONObject: movieDict)

        var request = authenticatedRequest(url: getURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    // Update (PUT) implementation
    func updateMovie(movie: Movie, moveFiles: Bool = false) async throws {
        // Fetch fresh movie data from API to get all required fields
        guard let getURL = URL(string: "\(baseURL)/movie/\(movie.id)") else {
            throw URLError(.badURL)
        }

        let getRequest = authenticatedRequest(url: getURL)
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        guard let httpGetResponse = getResponse as? HTTPURLResponse,
              (200...299).contains(httpGetResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse as dictionary to preserve all fields
        guard var movieDict = try JSONSerialization.jsonObject(with: getData) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        // Update only the fields we want to change
        movieDict["monitored"] = movie.monitored
        movieDict["qualityProfileId"] = movie.qualityProfileId
        if let minimumAvailability = movie.minimumAvailability {
            movieDict["minimumAvailability"] = minimumAvailability
        }
        if let tags = movie.tags {
            movieDict["tags"] = tags
        }
        movieDict = try MediaFolderPath.applyingRoot(movie.rootFolderPath, to: movieDict)

        // Convert back to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: movieDict)

        guard let url = URL(string: "\(baseURL)/movie/\(movie.id)?moveFiles=\(moveFiles)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate movies cache after update
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    /// Uses Radarr's native movie editor so multi-select actions are one atomic request.
    func editMovies(
        ids: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        minimumAvailability: RadarrMinimumAvailability? = nil,
        rootFolderPath: String? = nil,
        tagIds: [Int]? = nil,
        moveFiles: Bool = false
    ) async throws {
        guard !ids.isEmpty, let url = URL(string: "\(baseURL)/movie/editor") else {
            throw URLError(.badURL)
        }

        var payload: [String: Any] = ["movieIds": ids, "moveFiles": moveFiles]
        if let monitored { payload["monitored"] = monitored }
        if let qualityProfileId { payload["qualityProfileId"] = qualityProfileId }
        if let minimumAvailability { payload["minimumAvailability"] = minimumAvailability.rawValue }
        if let rootFolderPath { payload["rootFolderPath"] = rootFolderPath }
        if let tagIds {
            payload["tags"] = tagIds
            payload["applyTags"] = "replace"
        }

        try await sendJSONRequest(url: url, method: "PUT", payload: payload)
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    func deleteMovies(ids: [Int], deleteFiles: Bool, addImportExclusion: Bool = false) async throws {
        guard !ids.isEmpty, let url = URL(string: "\(baseURL)/movie/editor") else {
            throw URLError(.badURL)
        }
        try await sendJSONRequest(url: url, method: "DELETE", payload: [
            "movieIds": ids,
            "deleteFiles": deleteFiles,
            "addImportExclusion": addImportExclusion
        ])
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    func searchForMovies(ids: [Int]) async throws {
        guard !ids.isEmpty else { return }
        try await runCommand(name: "MoviesSearch", values: ["movieIds": ids])
    }

    func refreshMovie(movieId: Int) async throws {
        try await runCommand(name: "RefreshMovie", values: ["movieIds": [movieId]])
    }

    func renameMovie(movieId: Int) async throws {
        try await runCommand(name: "RenameMovie", values: ["movieIds": [movieId]])
    }

    private func runCommand(name: String, values: [String: Any] = [:]) async throws {
        guard let url = URL(string: "\(baseURL)/command") else { throw URLError(.badURL) }
        var payload = values
        payload["name"] = name
        try await sendJSONRequest(url: url, method: "POST", payload: payload)
    }

    private func sendJSONRequest(url: URL, method: String, payload: [String: Any]) async throws {
        var request = authenticatedRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errors = try? JSONDecoder().decode([RadarrErrorResponse].self, from: data),
               let message = errors.first?.errorMessage {
                throw RadarrError.apiError(message)
            }
            throw URLError(.badServerResponse)
        }
    }

    /// Tests the connection to the Radarr server using the provided URL and API key
    func testConnection(url: String, apiKey: String) async throws {
        let normalizedURL = ConfigurationManager.normalizedServerURL(url)
        guard let testURL = URL(string: "\(normalizedURL)/api/v3/system/status") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: testURL, apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

    }

    /// Invalidate all Radarr-related caches
    func invalidateCache() async {
        await CacheManager.shared.clearWithPrefix("radarr.")
    }

    // MARK: - Movie File Management

    /// Fetches movie files for a specific movie
    func fetchMovieFiles(movieId: Int) async throws -> [MovieFile] {
        let cacheKey = CacheManager.CacheKey.movieFiles(movieId)

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.short
        ) {
            try await self.fetchMovieFilesFromAPI(movieId: movieId)
        }
    }

    /// Direct API call to fetch movie files
    private func fetchMovieFilesFromAPI(movieId: Int) async throws -> [MovieFile] {
        guard let url = URL(string: "\(baseURL)/moviefile?movieId=\(movieId)") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let files = try JSONDecoder().decode([MovieFile].self, from: data)
        return files
    }

    /// Deletes a specific movie file (not the movie itself)
    func deleteMovieFile(id: Int, movieId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/moviefile/\(id)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate movie files cache and movies cache
        await CacheManager.shared.remove(CacheManager.CacheKey.movieFiles(movieId))
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrMovies)
    }

    /// Triggers a search for a movie in Radarr
    func searchForMovie(movieId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/command") else {
            throw URLError(.badURL)
        }

        let payload: [String: Any] = [
            "name": "MoviesSearch",
            "movieIds": [movieId]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchMovieReleases(movieId: Int) async throws -> [ReleaseSearchResult] {
        guard let url = URL(string: "\(baseURL)/release?movieId=\(movieId)") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([ReleaseSearchResult].self, from: data)
    }

    func grabRelease(_ release: ReleaseSearchResult) async throws {
        guard let indexerId = release.indexerId,
              let url = URL(string: "\(baseURL)/release") else {
            throw URLError(.badURL)
        }

        let payload: [String: Any] = [
            "guid": release.guid,
            "indexerId": indexerId
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await CacheManager.shared.remove(CacheManager.CacheKey.radarrQueue)
    }

    // MARK: - Logs

    /// Fetches the last N log entries from Radarr
    /// - Parameter count: Number of log entries to fetch (default: 10)
    func fetchLogs(count: Int = 10) async throws -> [LogEntry] {
        guard let url = URL(string: "\(baseURL)/log?pageSize=\(count)&sortKey=time&sortDirection=descending") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let logResponse = try JSONDecoder().decode(LogResponse.self, from: data)
        return logResponse.records
    }

    /// Fetches logs using specific URL and API key (for settings view)
    func fetchLogs(url: String, apiKey: String, count: Int = 10) async throws -> [LogEntry] {
        let normalizedURL = ConfigurationManager.normalizedServerURL(url)
        guard let logURL = URL(string: "\(normalizedURL)/api/v3/log?pageSize=\(count)&sortKey=time&sortDirection=descending") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: logURL, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let logResponse = try JSONDecoder().decode(LogResponse.self, from: data)
        return logResponse.records
    }

    // MARK: - Root Folders

    /// Fetches root folders with caching
    func fetchRootFolders(forceRefresh: Bool = false) async throws -> [RootFolder] {
        let cacheKey = CacheManager.CacheKey.radarrRootFolders

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.qualityProfiles, // Root folders rarely change
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchRootFoldersFromAPI()
        }
    }

    /// Direct API call for root folders
    private func fetchRootFoldersFromAPI() async throws -> [RootFolder] {
        guard let url = URL(string: "\(baseURL)/rootfolder") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let folders = try JSONDecoder().decode([RootFolder].self, from: data)
        return folders
    }

    // MARK: - Quality Profiles

    /// Fetches quality profiles with caching
    func fetchQualityProfiles(forceRefresh: Bool = false) async throws -> [RadarrQualityProfile] {
        let cacheKey = CacheManager.CacheKey.radarrQualityProfiles

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.qualityProfiles,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchQualityProfilesFromAPI()
        }
    }

    /// Direct API call for quality profiles
    private func fetchQualityProfilesFromAPI() async throws -> [RadarrQualityProfile] {
        guard let url = URL(string: "\(baseURL)/qualityprofile") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let profiles = try JSONDecoder().decode([RadarrQualityProfile].self, from: data)
        return profiles
    }

    // MARK: - Tags

    /// Fetches tags with caching
    func fetchTags(forceRefresh: Bool = false) async throws -> [MediaTag] {
        let cacheKey = CacheManager.CacheKey.radarrTags

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.qualityProfiles,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchTagsFromAPI()
        }
    }

    private func fetchTagsFromAPI() async throws -> [MediaTag] {
        guard let url = URL(string: "\(baseURL)/tag") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([MediaTag].self, from: data)
    }

    // MARK: - Queue (Activity)

    /// Fetches the download queue
    func fetchQueue(forceRefresh: Bool = false) async throws -> [QueueItem] {
        let cacheKey = CacheManager.CacheKey.radarrQueue

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.short,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchQueueFromAPI()
        }
    }

    /// Direct API call for queue
    private func fetchQueueFromAPI() async throws -> [QueueItem] {
        guard let url = URL(string: "\(baseURL)/queue?page=1&pageSize=100&includeUnknownMovieItems=false") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let queueResponse = try JSONDecoder().decode(QueueResponse.self, from: data)
        return queueResponse.records
    }

    /// Removes an item from the queue
    func removeFromQueue(id: Int, removeFromClient: Bool = true, blocklist: Bool = false) async throws {
        guard let url = URL(string: "\(baseURL)/queue/\(id)?removeFromClient=\(removeFromClient)&blocklist=\(blocklist)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate queue cache
        await CacheManager.shared.remove(CacheManager.CacheKey.radarrQueue)
    }

    // MARK: - History and Blocklist

    func fetchHistory(pageSize: Int = 50) async throws -> [ArrActivityRecord] {
        try await fetchActivityRecords(endpoint: "history", pageSize: pageSize)
    }

    func fetchBlocklist(pageSize: Int = 50) async throws -> [ArrActivityRecord] {
        try await fetchActivityRecords(endpoint: "blocklist", pageSize: pageSize)
    }

    func deleteBlocklistItem(id: Int) async throws {
        guard let url = URL(string: "\(baseURL)/blocklist/\(id)") else { throw URLError(.badURL) }
        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }
    }

    private func fetchActivityRecords(endpoint: String, pageSize: Int) async throws -> [ArrActivityRecord] {
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "sortKey", value: "date"),
            URLQueryItem(name: "sortDirection", value: "descending")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ArrActivityResponse.self, from: data).records
    }

    // MARK: - Collections

    func fetchCollections() async throws -> [RadarrCollection] {
        guard let url = URL(string: "\(baseURL)/collection") else { throw URLError(.badURL) }
        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([RadarrCollection].self, from: data)
    }

    func updateCollection(
        id: Int,
        monitored: Bool? = nil,
        monitorMovies: Bool? = nil,
        searchOnAdd: Bool? = nil
    ) async throws {
        guard let url = URL(string: "\(baseURL)/collection") else { throw URLError(.badURL) }
        var payload: [String: Any] = ["collectionIds": [id]]
        if let monitored { payload["monitored"] = monitored }
        if let monitorMovies { payload["monitorMovies"] = monitorMovies }
        if let searchOnAdd { payload["searchOnAdd"] = searchOnAdd }
        try await sendJSONRequest(url: url, method: "PUT", payload: payload)
    }

    // MARK: - Wanted/Missing

    /// Fetches movies that are missing (monitored, released, but no file)
    func fetchMissing() async throws -> [Movie] {
        let movies = try await fetchMovies()
        // Filter for monitored, released movies without files (checked via moviefile endpoint)
        let candidates = movies.filter { $0.monitored && ($0.status == "released" || $0.status == "inCinemas") }
        var missing: [Movie] = []
        for movie in candidates {
            let files = try await fetchMovieFiles(movieId: movie.id)
            if files.isEmpty {
                missing.append(movie)
            }
        }
        return missing
    }

    /// Fetches movies that are wanted (monitored, released, but no file) using parallel fetching
    func fetchWanted() async throws -> [Movie] {
        try await fetchPagedMovies(endpoint: "wanted/missing")
    }

    func fetchCutoffUnmet() async throws -> [Movie] {
        try await fetchPagedMovies(endpoint: "wanted/cutoff")
    }

    private func fetchPagedMovies(endpoint: String) async throws -> [Movie] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?page=1&pageSize=100&sortKey=title&sortDirection=ascending") else {
            throw URLError(.badURL)
        }
        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }
        struct Response: Codable { let records: [Movie] }
        return try JSONDecoder().decode(Response.self, from: data).records
    }

    // MARK: - Backups

    /// Fetches all backups from the Radarr server
    func fetchBackups(url: String, apiKey: String) async throws -> [ServerBackup] {
        let normalizedURL = ConfigurationManager.normalizedServerURL(url)
        guard let backupURL = URL(string: "\(normalizedURL)/api/v3/system/backup") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: backupURL, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let backups = try JSONDecoder().decode([ServerBackup].self, from: data)
        return backups.sorted { $0.time > $1.time }
    }

    /// Restores a backup on the Radarr server (triggers restart)
    func restoreBackup(url: String, apiKey: String, backupId: Int) async throws {
        let normalizedURL = ConfigurationManager.normalizedServerURL(url)
        guard let restoreURL = URL(string: "\(normalizedURL)/api/v3/system/backup/restore/\(backupId)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: restoreURL, apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate all caches after restore
        await invalidateCache()
    }
}
