import Foundation

// MARK: - Sonarr Error Types

enum SonarrError: LocalizedError {
    case apiError(String)
    case showAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return message
        case .showAlreadyExists(let title):
            return "\(title) is already in your library"
        }
    }
}

class SonarrService {
    static let shared = SonarrService()

    private let config = ConfigurationManager.shared

    private var baseURL: String {
        config.sonarrBaseURL
    }

    private var serverURL: String {
        config.sonarrURL
    }

    private var apiKey: String {
        config.sonarrAPIKey
    }

    private init() {}

    // MARK: - Request Helpers

    /// Creates an authenticated URLRequest with API key header and timeout
    private func authenticatedRequest(url: URL, apiKey: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(apiKey ?? self.apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    /// Generates a proper title slug for Sonarr
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

    /// Converts a relative image path from Sonarr to a full URL
    func imageURL(for relativePath: String) -> URL? {
        // Handle paths that are already full URLs
        if relativePath.hasPrefix("http") {
            return URL(string: relativePath)
        }
        // Prepend server URL to relative paths
        guard !serverURL.isEmpty else { return nil }
        return URL(string: serverURL + relativePath)
    }

    /// Fetches image data with proper authentication
    func fetchImageData(from url: URL) async throws -> Data {
        let request = authenticatedRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    // MARK: - Cached Methods

    /// Fetches quality profiles with long-term caching (24 hours)
    /// Quality profiles rarely change, so we cache them aggressively
    func fetchQualityProfiles(forceRefresh: Bool = false) async throws -> [QualityProfile] {
        let cacheKey = CacheManager.CacheKey.sonarrQualityProfiles

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
    private func fetchQualityProfilesFromAPI() async throws -> [QualityProfile] {
        guard let url = URL(string: "\(baseURL)/qualityprofile") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let profiles = try JSONDecoder().decode([QualityProfile].self, from: data)
        return profiles
    }

    /// Tests connection to Sonarr server with given credentials
    func testConnection(url: String, apiKey: String) async throws {
        guard let testURL = URL(string: "\(url)/api/v3/system/status") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: testURL, apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

    }

    /// Fetches all TV shows with caching
    func fetchShows(forceRefresh: Bool = false) async throws -> [TVShow] {
        let cacheKey = CacheManager.CacheKey.sonarrShows

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.library,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchShowsFromAPI()
        }
    }

    /// Direct API call for TV shows
    private func fetchShowsFromAPI() async throws -> [TVShow] {
        guard let url = URL(string: "\(baseURL)/series") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let shows = try JSONDecoder().decode([TVShow].self, from: data)
        return shows
    }

    /// Searches for TV shows with caching
    func searchShows(term: String) async throws -> [TVShowLookup] {
        let cacheKey = CacheManager.CacheKey.sonarrSearch(term)

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.search
        ) {
            try await self.searchShowsFromAPI(term: term)
        }
    }

    /// Direct API call for search
    private func searchShowsFromAPI(term: String) async throws -> [TVShowLookup] {
        var components = URLComponents(string: "\(baseURL)/series/lookup")
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

        let shows = try JSONDecoder().decode([TVShowLookup].self, from: data)
        return shows
    }

    /// Adds a new TV show to Sonarr
    @discardableResult
    func addShow(
        show: TVShowLookup,
        monitorOption: MonitorOption = .all,
        qualityProfileId: Int = 1,
        rootFolderPath: String = "/tv/",
        monitored: Bool = true,
        monitorNewItems: SonarrNewItemMonitor = .all,
        seriesType: SonarrSeriesType = .standard,
        seasonFolder: Bool = true,
        searchForMissingEpisodes: Bool = true,
        searchForCutoffUnmetEpisodes: Bool = false,
        tagIds: [Int] = []
    ) async throws -> TVShow {
        guard let url = URL(string: "\(baseURL)/series") else {
            throw URLError(.badURL)
        }

        // Sonarr requires specific payload structure for adding a series
        let payload: [String: Any] = [
            "title": show.title,
            "qualityProfileId": qualityProfileId,
            "titleSlug": generateTitleSlug(show.title, id: show.tvdbId),
            "images": [],
            "tvdbId": show.tvdbId,
            "year": show.year,
            "rootFolderPath": rootFolderPath,
            "monitored": monitored,
            "monitorNewItems": monitorNewItems.rawValue,
            "seriesType": seriesType.rawValue,
            "seasonFolder": seasonFolder,
            "tags": tagIds,
            "addOptions": [
                "monitor": monitorOption.rawValue,
                "searchForMissingEpisodes": searchForMissingEpisodes,
                "searchForCutoffUnmetEpisodes": searchForCutoffUnmetEpisodes
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
            // Try to parse Sonarr's error response for a better message
            if let errorResponse = try? JSONDecoder().decode([RadarrErrorResponse].self, from: data),
               let firstError = errorResponse.first {
                if firstError.errorMessage.lowercased().contains("already") ||
                   firstError.errorMessage.lowercased().contains("exists") {
                    throw SonarrError.showAlreadyExists(show.title)
                }
                throw SonarrError.apiError(firstError.errorMessage)
            }
            throw URLError(.badServerResponse)
        }

        // Invalidate shows cache after adding
        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrShows)

        let addedShow = try JSONDecoder().decode(TVShow.self, from: data)
        return addedShow
    }

    /// Updates an existing TV show in Sonarr
    func updateShow(show: TVShow) async throws {
        // Fetch fresh show data from API to get all required fields
        guard let getURL = URL(string: "\(baseURL)/series/\(show.id)") else {
            throw URLError(.badURL)
        }

        let getRequest = authenticatedRequest(url: getURL)
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        guard let httpGetResponse = getResponse as? HTTPURLResponse,
              (200...299).contains(httpGetResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse as dictionary to preserve all fields
        guard var showDict = try JSONSerialization.jsonObject(with: getData) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        // Update only the fields we want to change
        showDict["monitored"] = show.monitored
        showDict["qualityProfileId"] = show.qualityProfileId
        if let seriesType = show.seriesType {
            showDict["seriesType"] = seriesType
        }
        if let seasonFolder = show.seasonFolder {
            showDict["seasonFolder"] = seasonFolder
        }
        if let monitorNewItems = show.monitorNewItems {
            showDict["monitorNewItems"] = monitorNewItems
        }
        if let tags = show.tags {
            showDict["tags"] = tags
        }

        // Convert back to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: showDict)

        guard let url = URL(string: "\(baseURL)/series/\(show.id)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate shows cache after update
        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrShows)
    }

    /// Deletes a TV show from Sonarr
    func deleteShow(id: Int, deleteFiles: Bool = true, addImportExclusion: Bool = false) async throws {
        guard let url = URL(string: "\(baseURL)/series/\(id)?deleteFiles=\(deleteFiles)&addImportListExclusion=\(addImportExclusion)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate shows cache after deletion
        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrShows)
    }

    func updateShowMonitoring(seriesId: Int, monitored: Bool) async throws {
        guard let getURL = URL(string: "\(baseURL)/series/\(seriesId)") else {
            throw URLError(.badURL)
        }

        let getRequest = authenticatedRequest(url: getURL)
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        guard let httpGetResponse = getResponse as? HTTPURLResponse,
              (200...299).contains(httpGetResponse.statusCode),
              var showDict = try JSONSerialization.jsonObject(with: getData) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        showDict["monitored"] = monitored
        let jsonData = try JSONSerialization.data(withJSONObject: showDict)

        var request = authenticatedRequest(url: getURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrShows)
    }

    /// Invalidate all Sonarr-related caches
    func invalidateCache() async {
        await CacheManager.shared.clearWithPrefix("sonarr.")
    }

    // MARK: - Episode File Management

    /// Fetches all episode files for a specific TV show
    func fetchEpisodeFiles(seriesId: Int) async throws -> [EpisodeFile] {
        let cacheKey = CacheManager.CacheKey.episodeFiles(seriesId)

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.short
        ) {
            try await self.fetchEpisodeFilesFromAPI(seriesId: seriesId)
        }
    }

    /// Direct API call to fetch episode files
    private func fetchEpisodeFilesFromAPI(seriesId: Int) async throws -> [EpisodeFile] {
        guard let url = URL(string: "\(baseURL)/episodefile?seriesId=\(seriesId)") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let files = try JSONDecoder().decode([EpisodeFile].self, from: data)
        return files
    }

    /// Deletes a specific episode file
    func deleteEpisodeFile(id: Int, seriesId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/episodefile/\(id)") else {
            throw URLError(.badURL)
        }

        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Invalidate episode files cache and shows cache
        await CacheManager.shared.remove(CacheManager.CacheKey.episodeFiles(seriesId))
        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrShows)
    }

    /// Triggers a search for a TV show in Sonarr
    func searchForShow(seriesId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/command") else {
            throw URLError(.badURL)
        }

        let payload: [String: Any] = [
            "name": "SeriesSearch",
            "seriesId": seriesId
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

    // MARK: - Logs

    /// Fetches the last N log entries from Sonarr
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
        guard let logURL = URL(string: "\(url)/api/v3/log?pageSize=\(count)&sortKey=time&sortDirection=descending") else {
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
    func fetchRootFolders(forceRefresh: Bool = false) async throws -> [SonarrRootFolder] {
        let cacheKey = CacheManager.CacheKey.sonarrRootFolders

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
    private func fetchRootFoldersFromAPI() async throws -> [SonarrRootFolder] {
        guard let url = URL(string: "\(baseURL)/rootfolder") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let folders = try JSONDecoder().decode([SonarrRootFolder].self, from: data)
        return folders
    }

    // MARK: - Tags

    /// Fetches tags with caching
    func fetchTags(forceRefresh: Bool = false) async throws -> [MediaTag] {
        let cacheKey = CacheManager.CacheKey.sonarrTags

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

    // MARK: - Episodes

    /// Fetches all episodes for a series
    func fetchEpisodes(seriesId: Int, forceRefresh: Bool = false) async throws -> [Episode] {
        let cacheKey = CacheManager.CacheKey.episodes(seriesId)

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.library,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchEpisodesFromAPI(seriesId: seriesId)
        }
    }

    /// Direct API call for episodes
    private func fetchEpisodesFromAPI(seriesId: Int) async throws -> [Episode] {
        guard let url = URL(string: "\(baseURL)/episode?seriesId=\(seriesId)") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let episodes = try JSONDecoder().decode([Episode].self, from: data)
        return episodes
    }

    /// Updates episode monitored status
    func updateEpisode(episodeId: Int, monitored: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/episode/\(episodeId)") else {
            throw URLError(.badURL)
        }

        let getRequest = authenticatedRequest(url: url)
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        guard let httpGetResponse = getResponse as? HTTPURLResponse,
              (200...299).contains(httpGetResponse.statusCode),
              var episodeDict = try JSONSerialization.jsonObject(with: getData) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        episodeDict["monitored"] = monitored
        let jsonData = try JSONSerialization.data(withJSONObject: episodeDict, options: [])

        var request = authenticatedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func updateEpisodes(_ episodes: [Episode], monitored: Bool) async throws {
        for episode in episodes {
            try await updateEpisode(episodeId: episode.id, monitored: monitored)
        }
    }

    /// Triggers a search for a specific episode
    func searchForEpisode(episodeId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/command") else {
            throw URLError(.badURL)
        }

        let payload: [String: Any] = [
            "name": "EpisodeSearch",
            "episodeIds": [episodeId]
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

    func fetchEpisodeReleases(episodeId: Int) async throws -> [ReleaseSearchResult] {
        guard let url = URL(string: "\(baseURL)/release?episodeId=\(episodeId)") else {
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

        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrQueue)
    }

    // MARK: - Queue (Activity)

    /// Fetches the download queue
    func fetchQueue(forceRefresh: Bool = false) async throws -> [QueueItem] {
        let cacheKey = CacheManager.CacheKey.sonarrQueue

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
        guard let url = URL(string: "\(baseURL)/queue?page=1&pageSize=100&includeUnknownSeriesItems=false") else {
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
        await CacheManager.shared.remove(CacheManager.CacheKey.sonarrQueue)
    }

    // MARK: - Wanted/Missing

    /// Fetches wanted/missing episodes
    func fetchWanted(forceRefresh: Bool = false) async throws -> [Episode] {
        let cacheKey = CacheManager.CacheKey.sonarrWanted

        if forceRefresh {
            await CacheManager.shared.remove(cacheKey)
        }

        return try await CacheManager.shared.fetchWithCache(
            key: cacheKey,
            ttl: CacheManager.TTL.library,
            bypassInFlight: forceRefresh
        ) {
            try await self.fetchWantedFromAPI()
        }
    }

    /// Direct API call for wanted/missing
    private func fetchWantedFromAPI() async throws -> [Episode] {
        guard let url = URL(string: "\(baseURL)/wanted/missing?page=1&pageSize=100&sortKey=airDateUtc&sortDirection=descending&includeSeries=true") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse the paged response
        struct WantedResponse: Codable {
            let page: Int
            let pageSize: Int
            let totalRecords: Int
            let records: [Episode]
        }

        let wantedResponse = try JSONDecoder().decode(WantedResponse.self, from: data)
        return wantedResponse.records
    }

    // MARK: - Backups

    /// Fetches all backups from the Sonarr server
    func fetchBackups(url: String, apiKey: String) async throws -> [ServerBackup] {
        guard let backupURL = URL(string: "\(url)/api/v3/system/backup") else {
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

    /// Restores a backup on the Sonarr server (triggers restart)
    func restoreBackup(url: String, apiKey: String, backupId: Int) async throws {
        guard let restoreURL = URL(string: "\(url)/api/v3/system/backup/restore/\(backupId)") else {
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
