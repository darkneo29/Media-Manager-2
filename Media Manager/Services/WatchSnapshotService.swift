#if os(iOS)
import Foundation
import WatchConnectivity

@MainActor
final class WatchSnapshotService: NSObject {
    static let shared = WatchSnapshotService()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var activationStarted = false
    private var isRefreshing = false

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported(), !activationStarted else { return }
        activationStarted = true

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sync(movies: [Movie], tvShows: [TVShow], forceSend: Bool = false) {
        guard WCSession.isSupported() else { return }
        start()

        Task {
            await sendSnapshot(movies: movies, tvShows: tvShows, forceSend: forceSend)
        }
    }

    func refreshFromCurrentState(forceLibraryRefresh: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if forceLibraryRefresh {
            await LibraryStateManager.shared.loadAll(forceRefresh: true)
        }

        await sendSnapshot(
            movies: LibraryStateManager.shared.movies,
            tvShows: LibraryStateManager.shared.tvShows,
            forceSend: true
        )
    }

    private func sendSnapshot(movies: [Movie], tvShows: [TVShow], forceSend: Bool) async {
        let snapshot = await makeSnapshot(movies: movies, tvShows: tvShows)
        guard let payload = try? encoder.encode(snapshot) else { return }

        let context: [String: Any] = [WatchConnectivityKey.snapshot: payload]
        let session = WCSession.default

        guard session.activationState == .activated else { return }
        guard forceSend || session.isPaired else { return }

        do {
            try session.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Failed to update watch application context: \(error)")
            #endif
        }

        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { error in
                #if DEBUG
                print("Failed to send watch message: \(error)")
                #endif
            }
        }
    }

    private func makeSnapshot(movies: [Movie], tvShows: [TVShow]) async -> WatchDashboardSnapshot {
        let config = ConfigurationManager.shared
        let downloads = await makeDownloadSummary()
        let services = makeServiceSummaries(
            config: config,
            movies: movies,
            tvShows: tvShows,
            downloads: downloads
        )

        return WatchDashboardSnapshot(
            generatedAt: Date(),
            configuration: WatchConfigurationSummary(
                radarrConfigured: config.isRadarrConfigured,
                sonarrConfigured: config.isSonarrConfigured,
                sabnzbdConfigured: config.isSabNZBConfigured,
                unraidConfigured: config.isUnraidConfigured
            ),
            library: WatchLibrarySummary(
                movieCount: movies.count,
                showCount: tvShows.count
            ),
            services: services,
            downloads: downloads,
            upcoming: makeUpcomingItems(movies: movies, tvShows: tvShows)
        )
    }

    private func makeServiceSummaries(
        config: ConfigurationManager,
        movies: [Movie],
        tvShows: [TVShow],
        downloads: WatchDownloadsSummary
    ) -> [WatchServiceSummary] {
        let libraryState = LibraryStateManager.shared
        let radarrState: WatchServiceState = {
            guard config.isRadarrConfigured else { return .notConfigured }
            return libraryState.moviesErrorMessage == nil ? .ready : .warning
        }()
        let sonarrState: WatchServiceState = {
            guard config.isSonarrConfigured else { return .notConfigured }
            return libraryState.showsErrorMessage == nil ? .ready : .warning
        }()
        let sabState: WatchServiceState = {
            guard config.isSabNZBConfigured else { return .notConfigured }
            return downloads.errorMessage == nil ? .ready : .warning
        }()
        let unraidState: WatchServiceState = config.isUnraidConfigured ? .ready : .notConfigured

        return [
            WatchServiceSummary(
                id: "radarr",
                name: "Radarr",
                state: radarrState,
                detail: config.isRadarrConfigured ? "\(movies.count) movies" : "Set up on iPhone"
            ),
            WatchServiceSummary(
                id: "sonarr",
                name: "Sonarr",
                state: sonarrState,
                detail: config.isSonarrConfigured ? "\(tvShows.count) shows" : "Set up on iPhone"
            ),
            WatchServiceSummary(
                id: "sabnzbd",
                name: "SabNZB",
                state: sabState,
                detail: downloads.statusText
            ),
            WatchServiceSummary(
                id: "unraid",
                name: "Unraid",
                state: unraidState,
                detail: config.isUnraidConfigured ? "Configured" : "Set up on iPhone"
            )
        ]
    }

    private func makeDownloadSummary() async -> WatchDownloadsSummary {
        guard ConfigurationManager.shared.isSabNZBConfigured else {
            return .notConfigured
        }

        do {
            let queue = try await SabNZBService.shared.fetchQueue(limit: 8)
            let activeStatuses: Set<DownloadStatus> = [
                .downloading,
                .extracting,
                .verifying,
                .repairing,
                .fetching,
                .propagating,
                .moving,
                .running,
                .quickCheck
            ]
            let activeCount = queue.downloads.filter { activeStatuses.contains($0.status) }.count

            return WatchDownloadsSummary(
                isConfigured: true,
                isPaused: queue.paused,
                speedBytesPerSecond: queue.speed,
                activeCount: activeCount,
                queuedCount: queue.downloads.count,
                items: queue.downloads.prefix(4).map { download in
                    WatchDownloadItem(
                        id: download.id,
                        name: download.name,
                        status: download.status.rawValue,
                        progress: download.progress,
                        timeLeft: download.timeLeft,
                        speedBytesPerSecond: download.speed
                    )
                },
                errorMessage: nil
            )
        } catch {
            return WatchDownloadsSummary(
                isConfigured: true,
                isPaused: false,
                speedBytesPerSecond: 0,
                activeCount: 0,
                queuedCount: 0,
                items: [],
                errorMessage: "Unavailable"
            )
        }
    }

    private func makeUpcomingItems(movies: [Movie], tvShows: [TVShow]) -> [WatchUpcomingItem] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let upperBound = calendar.date(byAdding: .day, value: 30, to: startOfToday) ?? startOfToday
        let enabledFilters = ReleaseRadarService.persistedEnabledFilters()

        return CalendarEventBuilder.allEvents(movies: movies, tvShows: tvShows)
            .filter { event in
                event.date >= startOfToday &&
                event.date <= upperBound &&
                enabledFilters.contains(ReleaseRadarService.eventFilter(for: event))
            }
            .prefix(8)
            .map { event in
                let mediaId: Int
                let kind: String
                switch event.source {
                case .movie(let movie):
                    mediaId = movie.id
                    kind = "Movie"
                case .tvShow(let show):
                    mediaId = show.id
                    kind = "TV"
                }

                return WatchUpcomingItem(
                    id: event.id.uuidString,
                    title: event.title,
                    date: event.date,
                    kind: kind,
                    detail: event.typeLabel,
                    mediaId: mediaId
                )
            }
    }

    private func handle(command: String) async {
        switch command {
        case WatchConnectivityCommand.refreshSnapshot:
            await refreshFromCurrentState(forceLibraryRefresh: true)
        case WatchConnectivityCommand.toggleDownloads:
            await toggleDownloads()
            await refreshFromCurrentState(forceLibraryRefresh: false)
        default:
            break
        }
    }

    private func reply(for message: [String: Any]) async -> [String: Any] {
        guard let command = message[WatchConnectivityKey.command] as? String,
              let payload = message[WatchConnectivityKey.payload] as? Data else {
            return [:]
        }

        switch command {
        case WatchConnectivityCommand.searchMedia:
            guard let request = try? decoder.decode(WatchMediaSearchRequest.self, from: payload) else {
                return [:]
            }
            return encodedReply(await searchMedia(request: request))

        case WatchConnectivityCommand.addMedia:
            guard let request = try? decoder.decode(WatchMediaAddRequest.self, from: payload) else {
                return [:]
            }
            return encodedReply(await addMedia(request: request))

        default:
            return [:]
        }
    }

    private func encodedReply<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? encoder.encode(value) else { return [:] }
        return [WatchConnectivityKey.payload: data]
    }

    private func searchMedia(request: WatchMediaSearchRequest) async -> WatchMediaSearchResponse {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .failure(request: request, message: "Say a movie or show title first.")
        }

        do {
            switch request.kind {
            case .movie:
                guard ConfigurationManager.shared.isRadarrConfigured else {
                    return .failure(request: request, message: "Radarr is not configured on iPhone.")
                }

                let movies = try await RadarrService.shared.searchMovies(term: query)
                return WatchMediaSearchResponse(
                    requestId: request.id,
                    kind: request.kind,
                    query: query,
                    results: movies.prefix(8).map { movie in
                        WatchMediaSearchResult(
                            kind: .movie,
                            remoteId: movie.tmdbId,
                            title: movie.title,
                            year: movie.year,
                            subtitle: movie.runtime > 0 ? "\(movie.runtime)m" : "Movie",
                            overview: movie.overview,
                            runtime: movie.runtime,
                            seasonCount: nil,
                            network: nil
                        )
                    },
                    errorMessage: nil
                )

            case .tvShow:
                guard ConfigurationManager.shared.isSonarrConfigured else {
                    return .failure(request: request, message: "Sonarr is not configured on iPhone.")
                }

                let shows = try await SonarrService.shared.searchShows(term: query)
                return WatchMediaSearchResponse(
                    requestId: request.id,
                    kind: request.kind,
                    query: query,
                    results: shows.prefix(8).map { show in
                        let seasonLabel = show.seasonCount == 1 ? "1 season" : "\(show.seasonCount) seasons"
                        return WatchMediaSearchResult(
                            kind: .tvShow,
                            remoteId: show.tvdbId,
                            title: show.title,
                            year: show.year,
                            subtitle: show.seasonCount > 0 ? seasonLabel : (show.network ?? "TV Show"),
                            overview: show.overview,
                            runtime: nil,
                            seasonCount: show.seasonCount,
                            network: show.network
                        )
                    },
                    errorMessage: nil
                )
            }
        } catch {
            return .failure(request: request, message: "Search failed: \(error.localizedDescription)")
        }
    }

    private func addMedia(request: WatchMediaAddRequest) async -> WatchMediaAddResponse {
        do {
            switch request.result.kind {
            case .movie:
                guard ConfigurationManager.shared.isRadarrConfigured else {
                    return addFailure(request: request, message: "Radarr is not configured on iPhone.")
                }

                let qualityProfiles = try await RadarrService.shared.fetchQualityProfiles()
                let rootFolders = try await RadarrService.shared.fetchRootFolders()
                let tags = (try? await RadarrService.shared.fetchTags()) ?? []
                let preferences = AddMediaPreferences.shared.radarrSettings(
                    profiles: qualityProfiles,
                    rootFolders: rootFolders,
                    tags: tags
                )
                let lookup = MovieLookup(
                    radarrId: nil,
                    tmdbId: request.result.remoteId,
                    title: request.result.title,
                    year: request.result.year,
                    overview: request.result.overview,
                    runtime: request.result.runtime ?? 0,
                    images: nil
                )
                let addedMovie = try await RadarrService.shared.addMovie(
                    movie: lookup,
                    qualityProfileId: preferences.qualityProfileId,
                    rootFolderPath: preferences.rootFolderPath,
                    minimumAvailability: preferences.minimumAvailability,
                    monitored: preferences.monitored,
                    searchForMovie: preferences.searchForMovie,
                    tagIds: preferences.tagIds
                )

                LibraryStateManager.shared.addMovieLocally(addedMovie)
                await refreshFromCurrentState(forceLibraryRefresh: false)
                let searchStatus = preferences.searchForMovie ? " and started searching" : ""
                return WatchMediaAddResponse(
                    requestId: request.id,
                    resultId: request.result.id,
                    success: true,
                    message: "Added \(addedMovie.title)\(searchStatus)."
                )

            case .tvShow:
                guard ConfigurationManager.shared.isSonarrConfigured else {
                    return addFailure(request: request, message: "Sonarr is not configured on iPhone.")
                }

                let qualityProfiles = try await SonarrService.shared.fetchQualityProfiles()
                let rootFolders = try await SonarrService.shared.fetchRootFolders()
                let tags = (try? await SonarrService.shared.fetchTags()) ?? []
                let preferences = AddMediaPreferences.shared.sonarrSettings(
                    profiles: qualityProfiles,
                    rootFolders: rootFolders,
                    tags: tags
                )
                let lookup = TVShowLookup(
                    tvdbId: request.result.remoteId,
                    title: request.result.title,
                    year: request.result.year,
                    overview: request.result.overview,
                    statistics: nil,
                    network: request.result.network,
                    images: nil
                )
                let addedShow = try await SonarrService.shared.addShow(
                    show: lookup,
                    monitorOption: preferences.monitorOption,
                    qualityProfileId: preferences.qualityProfileId,
                    rootFolderPath: preferences.rootFolderPath,
                    monitored: preferences.monitored,
                    monitorNewItems: preferences.monitorNewItems,
                    seriesType: preferences.seriesType,
                    seasonFolder: preferences.seasonFolder,
                    searchForMissingEpisodes: preferences.searchForMissingEpisodes,
                    searchForCutoffUnmetEpisodes: preferences.searchForCutoffUnmetEpisodes,
                    tagIds: preferences.tagIds
                )

                LibraryStateManager.shared.addShowLocally(addedShow)
                await refreshFromCurrentState(forceLibraryRefresh: false)
                let searchStatus = preferences.searchForMissingEpisodes ? " and started searching" : ""
                return WatchMediaAddResponse(
                    requestId: request.id,
                    resultId: request.result.id,
                    success: true,
                    message: "Added \(addedShow.title)\(searchStatus)."
                )
            }
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("already") ||
                message.localizedCaseInsensitiveContains("exists") {
                return addFailure(request: request, message: "\(request.result.title) is already in your library.")
            }
            return addFailure(request: request, message: "Add failed: \(message)")
        }
    }

    private func addFailure(request: WatchMediaAddRequest, message: String) -> WatchMediaAddResponse {
        WatchMediaAddResponse(
            requestId: request.id,
            resultId: request.result.id,
            success: false,
            message: message
        )
    }

    private func toggleDownloads() async {
        guard ConfigurationManager.shared.isSabNZBConfigured else { return }

        do {
            let queue = try await SabNZBService.shared.fetchQueue(limit: 1)
            if queue.paused {
                try await SabNZBService.shared.resumeQueue()
            } else {
                try await SabNZBService.shared.pauseQueue()
            }
        } catch {
            #if DEBUG
            print("Failed to toggle SabNZB queue from watch: \(error)")
            #endif
        }
    }
}

extension WatchSnapshotService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor in
            await self.refreshFromCurrentState(forceLibraryRefresh: false)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message[WatchConnectivityKey.command] as? String else { return }
        Task { @MainActor in
            await self.handle(command: command)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let reply = await self.reply(for: message)
            replyHandler(reply)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = userInfo[WatchConnectivityKey.command] as? String else { return }
        Task { @MainActor in
            await self.handle(command: command)
        }
    }
}

#endif
