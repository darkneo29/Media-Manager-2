import SwiftUI
import Combine

struct DownloadsView: View {
    @ObservedObject private var configuration = ConfigurationManager.shared
    var isActiveTab: Bool = true

    @State private var selectedTab = 0
    @State private var activeDownloads: [Download] = []
    @State private var historyDownloads: [HistoryDownload] = []
    @State private var isQueuePaused = false
    @State private var currentSpeed: Int64 = 0
    @State private var isLoadingQueue = false
    @State private var isLoadingHistory = false
    @State private var queueErrorMessage: String?
    @State private var historyErrorMessage: String?
    @State private var showClearHistoryAlert = false
    @State private var isViewVisible = false

    // Activity queue state
    @State private var radarrQueue: [QueueItem] = []
    @State private var sonarrQueue: [QueueItem] = []
    @State private var isLoadingActivity = false
    @State private var activitySection = 0
    @State private var radarrHistory: [ArrActivityRecord] = []
    @State private var sonarrHistory: [ArrActivityRecord] = []
    @State private var radarrBlocklist: [ArrActivityRecord] = []
    @State private var sonarrBlocklist: [ArrActivityRecord] = []
    @State private var activityErrorMessage: String?

    // Wanted/Missing state
    @State private var wantedSection = 0
    @State private var wantedMovies: [Movie] = []
    @State private var wantedEpisodes: [Episode] = []
    @State private var cutoffMovies: [Movie] = []
    @State private var cutoffEpisodes: [Episode] = []
    @State private var isLoadingWanted = false

    // App lifecycle tracking keeps live polling limited to the visible queue.
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedTabs: Set<Int> = []

    private var isSabConfigured: Bool {
        configuration.isSabNZBConfigured
    }

    private var isRadarrConfigured: Bool {
        configuration.isRadarrConfigured
    }

    private var isSonarrConfigured: Bool {
        configuration.isSonarrConfigured
    }

    private var shouldPollActiveDownloads: Bool {
        DownloadsPollingPolicy.shouldPoll(
            isActiveTab: isActiveTab,
            isViewVisible: isViewVisible,
            isViewingActiveQueue: selectedTab == 0,
            scenePhase: scenePhase,
            isSabConfigured: isSabConfigured
        )
    }

    private var totalActivityCount: Int {
        radarrQueue.count + sonarrQueue.count
    }

    private var canRefreshSelectedTab: Bool {
        switch selectedTab {
        case 0, 3:
            return isSabConfigured
        case 1:
            return isRadarrConfigured || isSonarrConfigured
        case 2:
            return isRadarrConfigured || isSonarrConfigured
        default:
            return false
        }
    }

    private var isRefreshingSelectedTab: Bool {
        switch selectedTab {
        case 0:
            return isLoadingQueue
        case 1:
            return isLoadingActivity
        case 2:
            return isLoadingWanted
        case 3:
            return isLoadingHistory
        default:
            return false
        }
    }

    /// Check if we're on tvOS
    private var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    /// tvOS grid columns for 2-column layout
    private var tvOSGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: TVSizing.gridSpacing),
            GridItem(.flexible(), spacing: TVSizing.gridSpacing)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab picker with 4 tabs
                    Picker("View", selection: $selectedTab) {
                        Text("Active").tag(0)
                        if totalActivityCount > 0 {
                            Text("Activity (\(totalActivityCount))").tag(1)
                        } else {
                            Text("Activity").tag(1)
                        }
                        let wantedCount = wantedMovies.count + wantedEpisodes.count
                        if wantedCount > 0 {
                            Text("Wanted (\(wantedCount))").tag(2)
                        } else {
                            Text("Wanted").tag(2)
                        }
                        Text("History").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)

                    switch selectedTab {
                    case 0:
                        if !isSabConfigured {
                            notConfiguredView(service: "SabNZB")
                        } else {
                            activeDownloadsView
                        }
                    case 1:
                        activityView
                    case 2:
                        wantedView
                    case 3:
                        if !isSabConfigured {
                            notConfiguredView(service: "SabNZB")
                        } else {
                            historyView
                        }
                    default:
                        activeDownloadsView
                    }
                }
            }
            .navigationTitle("Downloads")
            .navBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if selectedTab == 3 && !historyDownloads.isEmpty {
                        Button("Clear All") {
                            showClearHistoryAlert = true
                        }
                        .foregroundColor(ColorPalette.error)
                    }

                    if canRefreshSelectedTab {
                        Button {
                            Task {
                                await refreshSelectedTab()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isRefreshingSelectedTab)
                        .accessibilityLabel("Refresh Downloads")
                    }
                }
            }
            .alert("Clear History", isPresented: $showClearHistoryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllHistory()
                }
            } message: {
                Text("Are you sure you want to clear all download history? This cannot be undone.")
            }
            .alert("Activity Error", isPresented: Binding(
                get: { activityErrorMessage != nil },
                set: { if !$0 { activityErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { activityErrorMessage = nil }
            } message: {
                Text(activityErrorMessage ?? "The request could not be completed.")
            }
            .onAppear {
                isViewVisible = true
            }
            .onDisappear {
                isViewVisible = false
            }
            .task(id: isActiveTab) {
                guard isActiveTab, selectedTab != 0 else { return }
                await loadSelectedTabData(for: selectedTab)
            }
            .task(id: shouldPollActiveDownloads) {
                guard shouldPollActiveDownloads else { return }
                await refreshQueue()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(DownloadsPollingPolicy.refreshIntervalSeconds))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    guard shouldPollActiveDownloads else { return }
                    await refreshQueue()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && isActiveTab && selectedTab != 0 {
                    let tab = selectedTab
                    Task {
                        await loadSelectedTabData(for: tab, force: true)
                    }
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                if isActiveTab && newValue != 0 {
                    Task {
                        await loadSelectedTabData(for: newValue, force: loadedTabs.contains(newValue))
                    }
                }
            }
        }
    }

    // MARK: - Not Configured View

    private func notConfiguredView(service: String) -> some View {
        PlaceholderView(
            icon: "gear",
            title: "\(service) Not Configured",
            description: "Go to Settings to configure your \(service) server"
        )
    }

    // MARK: - Activity View

    private var activityView: some View {
        VStack(spacing: 0) {
            if !isRadarrConfigured && !isSonarrConfigured {
                PlaceholderView(
                    icon: "gear",
                    title: "No Services Configured",
                    description: "Configure Radarr or Sonarr in Settings to see download activity"
                )
            } else {
                Picker("Activity", selection: $activitySection) {
                    Text("Queue").tag(0)
                    Text("History").tag(1)
                    Text("Blocklist").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)

                if isLoadingActivity && radarrQueue.isEmpty && sonarrQueue.isEmpty && radarrHistory.isEmpty && sonarrHistory.isEmpty {
                    loadingView
                } else {
                    switch activitySection {
                    case 0:
                        queueActivityView
                    case 1:
                        arrRecordsView(radarr: radarrHistory, sonarr: sonarrHistory, isBlocklist: false)
                    default:
                        arrRecordsView(radarr: radarrBlocklist, sonarr: sonarrBlocklist, isBlocklist: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queueActivityView: some View {
        if radarrQueue.isEmpty && sonarrQueue.isEmpty {
            emptyActivityView
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    if !radarrQueue.isEmpty {
                        DownloadsSectionHeader(title: "Movies", icon: "film.fill")
                            .padding(.horizontal, AppSpacing.md)
                        ForEach(radarrQueue) { item in
                            ActivityQueueCard(item: item, type: .movie) { blocklist in
                                await removeFromRadarrQueue(item, blocklist: blocklist)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                    if !sonarrQueue.isEmpty {
                        DownloadsSectionHeader(title: "TV Shows", icon: "tv.fill")
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, radarrQueue.isEmpty ? 0 : AppSpacing.md)
                        ForEach(sonarrQueue) { item in
                            ActivityQueueCard(item: item, type: .tvShow) { blocklist in
                                await removeFromSonarrQueue(item, blocklist: blocklist)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                }
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .refreshable { await refreshActivityData() }
        }
    }

    @ViewBuilder
    private func arrRecordsView(
        radarr: [ArrActivityRecord],
        sonarr: [ArrActivityRecord],
        isBlocklist: Bool
    ) -> some View {
        if radarr.isEmpty && sonarr.isEmpty {
            PlaceholderView(
                icon: isBlocklist ? "hand.raised" : "clock.arrow.circlepath",
                title: isBlocklist ? "Blocklist is Empty" : "No Recent History",
                description: isBlocklist ? "Rejected releases will appear here" : "Radarr and Sonarr activity will appear here"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    if !radarr.isEmpty {
                        DownloadsSectionHeader(title: "Movies", icon: "film.fill")
                            .padding(.horizontal, AppSpacing.md)
                        ForEach(radarr) { record in
                            ArrActivityCard(record: record, type: .movie, canDelete: isBlocklist) {
                                await deleteBlocklistRecord(record, type: .movie)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                    if !sonarr.isEmpty {
                        DownloadsSectionHeader(title: "TV Shows", icon: "tv.fill")
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, radarr.isEmpty ? 0 : AppSpacing.md)
                        ForEach(sonarr) { record in
                            ArrActivityCard(record: record, type: .tvShow, canDelete: isBlocklist) {
                                await deleteBlocklistRecord(record, type: .tvShow)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                }
                .padding(.bottom, AppSpacing.xl)
            }
            .refreshable { await refreshActivityData() }
        }
    }

    private var emptyActivityView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.primary.opacity(0.4),
                                ColorPalette.secondary.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 50))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            Text("No Active Grabs")
                .font(AppTypography.headline())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text("Radarr and Sonarr aren't grabbing anything right now")
                .font(AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Wanted View

    private var wantedView: some View {
        VStack(spacing: 0) {
            if !isRadarrConfigured && !isSonarrConfigured {
                PlaceholderView(
                    icon: "gear",
                    title: "No Services Configured",
                    description: "Configure Radarr or Sonarr to see missing and cutoff-unmet media"
                )
            } else {
                Picker("Wanted", selection: $wantedSection) {
                    Text("Missing").tag(0)
                    Text("Cutoff Unmet").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)

                if isLoadingWanted && wantedMovies.isEmpty && wantedEpisodes.isEmpty && cutoffMovies.isEmpty && cutoffEpisodes.isEmpty {
                    loadingView
                } else if wantedSection == 0 {
                    wantedRecordsView(movies: wantedMovies, episodes: wantedEpisodes)
                } else {
                    wantedRecordsView(movies: cutoffMovies, episodes: cutoffEpisodes)
                }
            }
        }
    }

    @ViewBuilder
    private func wantedRecordsView(movies: [Movie], episodes: [Episode]) -> some View {
        if movies.isEmpty && episodes.isEmpty {
            emptyWantedView
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    if !movies.isEmpty {
                        DownloadsSectionHeader(title: "Movies", icon: "film.fill")
                        ForEach(movies) { movie in
                            WantedMovieCard(movie: movie) { await searchForMovie(movie) }
                        }
                    }
                    if !episodes.isEmpty {
                        DownloadsSectionHeader(title: "TV Episodes", icon: "tv.fill")
                            .padding(.top, movies.isEmpty ? 0 : AppSpacing.sm)
                        ForEach(episodes) { episode in
                            WantedEpisodeCard(episode: episode) { await searchForEpisode(episode) }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xl)
            }
            .refreshable { await refreshWantedData() }
        }
    }

    private var emptyWantedView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.success.opacity(0.4),
                                ColorPalette.secondary.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "checkmark.circle")
                    .font(.system(size: 50))
                    .foregroundColor(ColorPalette.success)
            }

            Text("All Caught Up!")
                .font(AppTypography.headline())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text(wantedSection == 0 ? "No missing media to download" : "Everything meets its quality cutoff")
                .font(AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)

            Spacer()
        }
    }

    // MARK: - Active Downloads View

    private var activeDownloadsView: some View {
        VStack(spacing: 0) {
            // Queue controls header
            queueControlsHeader
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)

            if isLoadingQueue && activeDownloads.isEmpty {
                loadingView
            } else if let queueErrorMessage, activeDownloads.isEmpty {
                downloadErrorView(
                    title: "Couldn't Load Downloads",
                    message: queueErrorMessage,
                    retry: {
                        await refreshQueue()
                    }
                )
            } else if activeDownloads.isEmpty {
                emptyActiveView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(activeDownloads) { download in
                            DownloadCard(
                                download: download,
                                onPauseResume: {
                                    toggleDownloadPause(download)
                                },
                                onDelete: {
                                    deleteDownload(download)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }
                .refreshable {
                    await refreshQueue()
                }
            }
        }
    }

    private var queueControlsHeader: some View {
        HStack {
            // Pause/Resume Queue button
            Button(action: toggleQueuePause) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: isQueuePaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .semibold))

                    Text(isQueuePaused ? "Resume Queue" : "Pause Queue")
                        .font(AppTypography.caption1(.semibold))
                }
                .foregroundColor(isQueuePaused ? ColorPalette.success : ColorPalette.warning)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    (isQueuePaused ? ColorPalette.success : ColorPalette.warning).opacity(0.15)
                )
                .cornerRadius(AppRadius.sm)
            }

            Spacer()

            if shouldPollActiveDownloads {
                HStack(spacing: AppSpacing.xxs) {
                    Circle()
                        .fill(ColorPalette.success)
                        .frame(width: 7, height: 7)

                    Text("Live")
                        .font(AppTypography.caption2(.semibold))
                        .foregroundColor(ColorPalette.success)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Live updates every five seconds")
            }

            // Speed indicator
            if currentSpeed > 0 {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ColorPalette.secondary)

                    Text(formatSpeed(currentSpeed))
                        .font(AppTypography.caption1(.semibold))
                        .foregroundColor(ColorPalette.secondary)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(ColorPalette.secondary.opacity(0.15))
                .cornerRadius(AppRadius.sm)
            }
        }
    }

    // MARK: - History View

    private var historyView: some View {
        Group {
            if isLoadingHistory && historyDownloads.isEmpty {
                loadingView
            } else if let historyErrorMessage, historyDownloads.isEmpty {
                downloadErrorView(
                    title: "Couldn't Load History",
                    message: historyErrorMessage,
                    retry: {
                        await refreshHistory()
                    }
                )
            } else if historyDownloads.isEmpty {
                emptyHistoryView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(historyDownloads) { download in
                            HistoryCard(
                                download: download,
                                onDelete: {
                                    deleteHistoryItem(download)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }
                .refreshable {
                    await refreshHistory()
                }
            }
        }
    }

    // MARK: - Empty States

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.secondary))
                .scaleEffect(1.5)
            Text("Loading...")
                .font(AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .padding(.top, AppSpacing.md)
            Spacer()
        }
    }

    private func downloadErrorView(title: String, message: String, retry: @escaping () async -> Void) -> some View {
        PlaceholderView(
            icon: "wifi.exclamationmark",
            title: title,
            description: message,
            action: PlaceholderView.ActionConfig(
                title: "Try Again",
                icon: "arrow.clockwise",
                handler: {
                    Task {
                        await retry()
                    }
                }
            )
        )
    }

    private var emptyActiveView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.secondary.opacity(0.4),
                                ColorPalette.info.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "tray")
                    .font(.system(size: 50))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            Text("No Active Downloads")
                .font(AppTypography.headline())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text("Your download queue is empty")
                .font(AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)

            Spacer()
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.primary.opacity(0.4),
                                ColorPalette.secondary.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 50))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            Text("No Download History")
                .font(AppTypography.headline())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text("Completed downloads will appear here")
                .font(AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)

            Spacer()
        }
    }

    // MARK: - Data Loading

    private func loadSelectedTabData(for tab: Int, force: Bool = false) async {
        guard isActiveTab else { return }
        if !force && loadedTabs.contains(tab) {
            return
        }

        switch tab {
        case 0:
            await loadData()
        case 1:
            await loadActivityData()
        case 2:
            await loadWantedData()
        case 3:
            await loadHistory()
        default:
            break
        }

        guard !Task.isCancelled else { return }
        loadedTabs.insert(tab)
    }

    private func loadData() async {
        guard isSabConfigured else { return }
        await refreshQueue()
    }

    private func loadHistory() async {
        guard isSabConfigured else { return }
        isLoadingHistory = true
        await refreshHistory()
        isLoadingHistory = false
    }

    private func loadActivityData() async {
        isLoadingActivity = true
        await refreshActivityData()
        isLoadingActivity = false
    }

    private func loadWantedData() async {
        guard isRadarrConfigured || isSonarrConfigured else { return }
        isLoadingWanted = true
        await refreshWantedData()
        isLoadingWanted = false
    }

    private func refreshActivityData() async {
        await MainActor.run { activityErrorMessage = nil }
        // Fetch queue, history, and blocklist in parallel for both services.
        await withTaskGroup(of: Void.self) { group in
            if isRadarrConfigured {
                group.addTask {
                    do {
                        let queue = try await RadarrService.shared.fetchQueue(forceRefresh: true)
                        await MainActor.run {
                            self.radarrQueue = queue
                        }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Radarr activity failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await RadarrService.shared.fetchHistory()
                        await MainActor.run { self.radarrHistory = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Radarr history failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await RadarrService.shared.fetchBlocklist()
                        await MainActor.run { self.radarrBlocklist = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Radarr blocklist failed: \(error.localizedDescription)" }
                    }
                }
            }

            if isSonarrConfigured {
                group.addTask {
                    do {
                        let queue = try await SonarrService.shared.fetchQueue(forceRefresh: true)
                        await MainActor.run {
                            self.sonarrQueue = queue
                        }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Sonarr activity failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await SonarrService.shared.fetchHistory()
                        await MainActor.run { self.sonarrHistory = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Sonarr history failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await SonarrService.shared.fetchBlocklist()
                        await MainActor.run { self.sonarrBlocklist = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Sonarr blocklist failed: \(error.localizedDescription)" }
                    }
                }
            }
        }
    }

    private func refreshWantedData() async {
        await withTaskGroup(of: Void.self) { group in
            if isRadarrConfigured {
                group.addTask {
                    do {
                        let records = try await RadarrService.shared.fetchWanted()
                        await MainActor.run { self.wantedMovies = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Radarr wanted failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await RadarrService.shared.fetchCutoffUnmet()
                        await MainActor.run { self.cutoffMovies = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Radarr cutoff failed: \(error.localizedDescription)" }
                    }
                }
            }
            if isSonarrConfigured {
                group.addTask {
                    do {
                        let records = try await SonarrService.shared.fetchWanted(forceRefresh: true)
                        await MainActor.run { self.wantedEpisodes = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Sonarr wanted failed: \(error.localizedDescription)" }
                    }
                }
                group.addTask {
                    do {
                        let records = try await SonarrService.shared.fetchCutoffUnmet()
                        await MainActor.run { self.cutoffEpisodes = records }
                    } catch {
                        await MainActor.run { self.activityErrorMessage = "Sonarr cutoff failed: \(error.localizedDescription)" }
                    }
                }
            }
        }
    }

    private func removeFromRadarrQueue(_ item: QueueItem, blocklist: Bool) async {
        do {
            try await RadarrService.shared.removeFromQueue(id: item.id, blocklist: blocklist)
            await MainActor.run {
                radarrQueue.removeAll { $0.id == item.id }
            }
        } catch {
            await MainActor.run { activityErrorMessage = "Could not remove Radarr item: \(error.localizedDescription)" }
        }
    }

    private func removeFromSonarrQueue(_ item: QueueItem, blocklist: Bool) async {
        do {
            try await SonarrService.shared.removeFromQueue(id: item.id, blocklist: blocklist)
            await MainActor.run {
                sonarrQueue.removeAll { $0.id == item.id }
            }
        } catch {
            await MainActor.run { activityErrorMessage = "Could not remove Sonarr item: \(error.localizedDescription)" }
        }
    }

    private func deleteBlocklistRecord(_ record: ArrActivityRecord, type: MediaType) async {
        do {
            switch type {
            case .movie:
                try await RadarrService.shared.deleteBlocklistItem(id: record.id)
                await MainActor.run { radarrBlocklist.removeAll { $0.id == record.id } }
            case .tvShow:
                try await SonarrService.shared.deleteBlocklistItem(id: record.id)
                await MainActor.run { sonarrBlocklist.removeAll { $0.id == record.id } }
            }
        } catch {
            await MainActor.run { activityErrorMessage = "Could not clear blocklist item: \(error.localizedDescription)" }
        }
    }

    private func searchForEpisode(_ episode: Episode) async {
        do {
            try await SonarrService.shared.searchForEpisode(episodeId: episode.id)
        } catch {
            await MainActor.run { activityErrorMessage = "Could not search for episode: \(error.localizedDescription)" }
        }
    }

    private func searchForMovie(_ movie: Movie) async {
        do {
            try await RadarrService.shared.searchForMovie(movieId: movie.id)
        } catch {
            await MainActor.run { activityErrorMessage = "Could not search for movie: \(error.localizedDescription)" }
        }
    }

    private func refreshSelectedTab() async {
        loadedTabs.insert(selectedTab)
        switch selectedTab {
        case 0:
            await loadData()
        case 1:
            await loadActivityData()
        case 2:
            await loadWantedData()
        case 3:
            await loadHistory()
        default:
            break
        }
    }

    private func refreshQueue() async {
        guard !isLoadingQueue else { return }
        isLoadingQueue = true
        defer { isLoadingQueue = false }

        do {
            let queue = try await SabNZBService.shared.fetchQueue()
            guard !Task.isCancelled else { return }
            activeDownloads = queue.downloads
            isQueuePaused = queue.paused
            currentSpeed = queue.speed
            queueErrorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            queueErrorMessage = "Failed to load downloads: \(error.localizedDescription)"
        }
    }

    private func refreshHistory() async {
        do {
            let history = try await SabNZBService.shared.fetchHistory()
            await MainActor.run {
                historyDownloads = history
                historyErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                historyErrorMessage = "Failed to load history: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Actions

    private func toggleQueuePause() {
        Task {
            do {
                if isQueuePaused {
                    try await SabNZBService.shared.resumeQueue()
                } else {
                    try await SabNZBService.shared.pauseQueue()
                }
                await refreshQueue()
            } catch {
                await MainActor.run {
                    queueErrorMessage = "Failed to update queue: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleDownloadPause(_ download: Download) {
        Task {
            do {
                if download.status == .paused {
                    try await SabNZBService.shared.resumeDownload(id: download.id)
                } else {
                    try await SabNZBService.shared.pauseDownload(id: download.id)
                }
                await refreshQueue()
            } catch {
                await MainActor.run {
                    queueErrorMessage = "Failed to update download: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteDownload(_ download: Download) {
        Task {
            do {
                try await SabNZBService.shared.deleteDownload(id: download.id)
                await refreshQueue()
            } catch {
                await MainActor.run {
                    queueErrorMessage = "Failed to delete download: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteHistoryItem(_ download: HistoryDownload) {
        Task {
            do {
                try await SabNZBService.shared.deleteHistoryItem(id: download.id)
                await refreshHistory()
            } catch {
                await MainActor.run {
                    historyErrorMessage = "Failed to delete history item: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearAllHistory() {
        Task {
            do {
                try await SabNZBService.shared.clearHistory()
                await refreshHistory()
            } catch {
                await MainActor.run {
                    historyErrorMessage = "Failed to clear history: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        let mbPerSec = Double(bytesPerSec) / (1024 * 1024)
        if mbPerSec >= 1 {
            return String(format: "%.1f MB/s", mbPerSec)
        } else {
            let kbPerSec = Double(bytesPerSec) / 1024
            return String(format: "%.0f KB/s", kbPerSec)
        }
    }
}

// MARK: - Activity Queue Card

enum MediaType {
    case movie
    case tvShow
}

struct ActivityQueueCard: View {
    let item: QueueItem
    let type: MediaType
    let onRemove: (Bool) async -> Void

    @State private var isRemoving = false
    @State private var showingRemoveOptions = false

    private var statusColor: Color {
        if item.hasIssue {
            return ColorPalette.warning
        }
        return ColorPalette.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Title row
            HStack {
                Image(systemName: type == .movie ? "film.fill" : "tv.fill")
                    .font(.system(size: 14))
                    .foregroundColor(type == .movie ? ColorPalette.primary : ColorPalette.secondary)

                Text(item.title)
                    .font(AppTypography.subheadline(.medium))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)

                Spacer()

                // Remove button
                Button(action: { showingRemoveOptions = true }) {
                    if isRemoving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                }
                .disabled(isRemoving)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ColorPalette.divider)
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geometry.size.width * (item.progress / 100), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)

            // Status row
            HStack {
                // Status badge
                Text(item.statusDisplay)
                    .font(AppTypography.caption2(.medium))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(AppRadius.sm)

                Spacer()

                // Size info
                Text("\(item.formattedRemaining) left of \(item.formattedSize)")
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)

                if let timeleft = item.timeleft, !timeleft.isEmpty {
                    Text("• \(timeleft)")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }
            }

            // Warning messages
            if let messages = item.statusMessages, !messages.isEmpty {
                ForEach(messages.compactMap { $0.title }, id: \.self) { message in
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ColorPalette.warning)
                        Text(message)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.warning)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .confirmationDialog("Remove download?", isPresented: $showingRemoveOptions, titleVisibility: .visible) {
            Button("Remove and Block Release", role: .destructive) {
                remove(blocklist: true)
            }
            Button("Remove from Queue Only", role: .destructive) {
                remove(blocklist: false)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Blocking prevents Radarr or Sonarr from grabbing this same release again.")
        }
    }

    private func remove(blocklist: Bool) {
        isRemoving = true
        Task {
            await onRemove(blocklist)
            await MainActor.run { isRemoving = false }
        }
    }
}

private struct ArrActivityCard: View {
    let record: ArrActivityRecord
    let type: MediaType
    let canDelete: Bool
    let onDelete: () async -> Void

    @State private var isDeleting = false

    private var dateText: String? {
        record.parsedDate?.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: type == .movie ? "film.fill" : "tv.fill")
                .foregroundColor(type == .movie ? ColorPalette.primary : ColorPalette.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(record.displayTitle)
                    .font(AppTypography.subheadline(.medium))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(2)

                HStack(spacing: AppSpacing.xs) {
                    Text(record.displayEvent)
                    if let dateText { Text("• \(dateText)") }
                }
                .font(AppTypography.caption2())
                .foregroundColor(ColorPalette.textMutedDark)

                if let message = record.message, !message.isEmpty {
                    Text(message)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.warning)
                        .lineLimit(2)
                }
            }

            Spacer()

            if canDelete {
                Button {
                    isDeleting = true
                    Task {
                        await onDelete()
                        await MainActor.run { isDeleting = false }
                    }
                } label: {
                    if isDeleting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "trash")
                            .foregroundColor(ColorPalette.error)
                    }
                }
                .disabled(isDeleting)
                .accessibilityLabel("Remove from blocklist")
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
    }
}

// MARK: - Downloads Section Header

private struct DownloadsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ColorPalette.primary)

            Text(title)
                .font(AppTypography.subheadline(.semibold))
                .foregroundColor(ColorPalette.textPrimaryDark)
        }
    }
}

// MARK: - Wanted Episode Card

struct WantedMovieCard: View {
    let movie: Movie
    let onSearch: () async -> Void

    @State private var isSearching = false

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(movie.title)
                    .font(AppTypography.subheadline(.medium))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)
                Text("\(movie.year) • \(movie.minimumAvailabilityDisplayName ?? "Monitored")")
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            Spacer()
            Button {
                isSearching = true
                Task {
                    await onSearch()
                    await MainActor.run { isSearching = false }
                }
            } label: {
                if isSearching {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .tint(ColorPalette.primary)
            .disabled(isSearching)
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
    }
}

struct WantedEpisodeCard: View {
    let episode: Episode
    let onSearch: () async -> Void

    @State private var isSearching = false

    private var formattedAirDate: String {
        guard let airDate = episode.airDateParsed else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: airDate)
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                // Series title
                if let seriesTitle = episode.series?.title {
                    Text(seriesTitle)
                        .font(AppTypography.subheadline(.medium))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(1)
                }

                // Episode code and title
                HStack(spacing: AppSpacing.xs) {
                    Text(episode.episodeCode)
                        .font(AppTypography.caption1(.semibold))
                        .foregroundColor(ColorPalette.secondary)

                    if let title = episode.title {
                        Text("•")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(title)
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.textMutedDark)
                    Text(formattedAirDate)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }
            }

            Spacer()

            // Search button
            Button(action: {
                isSearching = true
                Task {
                    await onSearch()
                    isSearching = false
                }
            }) {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(ColorPalette.primary)
            .cornerRadius(AppRadius.sm)
            .disabled(isSearching)
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
    }
}

#Preview {
    DownloadsView()
        .preferredColorScheme(.dark)
}
