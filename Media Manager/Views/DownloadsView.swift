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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showClearHistoryAlert = false
    // refreshTimer removed - using .task modifier instead

    // Activity queue state
    @State private var radarrQueue: [QueueItem] = []
    @State private var sonarrQueue: [QueueItem] = []
    @State private var isLoadingActivity = false

    // Wanted/Missing state
    @State private var wantedEpisodes: [Episode] = []
    @State private var isLoadingWanted = false

    // App lifecycle tracking for timer optimization
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime: Date?
    @State private var loadedTabs: Set<Int> = []
    private let minimumRefreshInterval: TimeInterval = 2 // Prevent rapid refreshes

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
            scenePhase: scenePhase,
            isSabConfigured: isSabConfigured
        ) && selectedTab == 0
    }

    private var totalActivityCount: Int {
        radarrQueue.count + sonarrQueue.count
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
                        if wantedEpisodes.count > 0 {
                            Text("Wanted (\(wantedEpisodes.count))").tag(2)
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
                if selectedTab == 3 && !historyDownloads.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear All") {
                            showClearHistoryAlert = true
                        }
                        .foregroundColor(ColorPalette.error)
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
            .task(id: isActiveTab) {
                guard isActiveTab else { return }
                await loadSelectedTabData()
            }
            .task(id: shouldPollActiveDownloads) {
                guard shouldPollActiveDownloads else { return }
                await refreshQueue()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await throttledRefresh()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && isActiveTab {
                    Task {
                        await loadSelectedTabData(force: true)
                    }
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                if isActiveTab {
                    Task {
                        await loadSelectedTabData(force: loadedTabs.contains(newValue))
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
        Group {
            if !isRadarrConfigured && !isSonarrConfigured {
                PlaceholderView(
                    icon: "gear",
                    title: "No Services Configured",
                    description: "Configure Radarr or Sonarr in Settings to see download activity"
                )
            } else if isLoadingActivity && radarrQueue.isEmpty && sonarrQueue.isEmpty {
                loadingView
            } else if radarrQueue.isEmpty && sonarrQueue.isEmpty {
                emptyActivityView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        // Radarr queue
                        if !radarrQueue.isEmpty {
                            DownloadsSectionHeader(title: "Movies", icon: "film.fill")
                                .padding(.horizontal, AppSpacing.md)

                            ForEach(radarrQueue) { item in
                                ActivityQueueCard(item: item, type: .movie, onRemove: {
                                    await removeFromRadarrQueue(item)
                                })
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }

                        // Sonarr queue
                        if !sonarrQueue.isEmpty {
                            DownloadsSectionHeader(title: "TV Shows", icon: "tv.fill")
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.top, radarrQueue.isEmpty ? 0 : AppSpacing.md)

                            ForEach(sonarrQueue) { item in
                                ActivityQueueCard(item: item, type: .tvShow, onRemove: {
                                    await removeFromSonarrQueue(item)
                                })
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                    }
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }
                .refreshable {
                    await refreshActivityData()
                }
            }
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
        Group {
            if !isSonarrConfigured {
                PlaceholderView(
                    icon: "gear",
                    title: "Sonarr Not Configured",
                    description: "Configure Sonarr in Settings to see wanted episodes"
                )
            } else if isLoadingWanted && wantedEpisodes.isEmpty {
                loadingView
            } else if wantedEpisodes.isEmpty {
                emptyWantedView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(wantedEpisodes) { episode in
                            WantedEpisodeCard(episode: episode, onSearch: {
                                await searchForEpisode(episode)
                            })
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }
                .refreshable {
                    await refreshWantedData()
                }
            }
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

            Text("No missing episodes to download")
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

            if isLoading && activeDownloads.isEmpty {
                loadingView
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
                    await throttledRefresh()
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
            if isLoading && historyDownloads.isEmpty {
                loadingView
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

    private func loadSelectedTabData(force: Bool = false) async {
        guard isActiveTab else { return }
        if !force && loadedTabs.contains(selectedTab) {
            return
        }

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

        loadedTabs.insert(selectedTab)
    }

    private func loadData() async {
        guard isSabConfigured else { return }
        isLoading = true
        await refreshQueue()
        isLoading = false
    }

    private func loadHistory() async {
        guard isSabConfigured else { return }
        isLoading = true
        await refreshHistory()
        isLoading = false
    }

    private func loadActivityData() async {
        isLoadingActivity = true
        await refreshActivityData()
        isLoadingActivity = false
    }

    private func loadWantedData() async {
        guard isSonarrConfigured else { return }
        isLoadingWanted = true
        await refreshWantedData()
        isLoadingWanted = false
    }

    private func refreshActivityData() async {
        // Fetch both queues in parallel
        await withTaskGroup(of: Void.self) { group in
            if isRadarrConfigured {
                group.addTask {
                    do {
                        let queue = try await RadarrService.shared.fetchQueue(forceRefresh: true)
                        await MainActor.run {
                            self.radarrQueue = queue
                        }
                    } catch {
                        #if DEBUG
                        print("Error loading Radarr queue: \(error)")
                        #endif
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
                        #if DEBUG
                        print("Error loading Sonarr queue: \(error)")
                        #endif
                    }
                }
            }
        }
    }

    private func refreshWantedData() async {
        guard isSonarrConfigured else { return }
        do {
            let episodes = try await SonarrService.shared.fetchWanted(forceRefresh: true)
            await MainActor.run {
                self.wantedEpisodes = episodes
            }
        } catch {
            #if DEBUG
            print("Error loading wanted episodes: \(error)")
            #endif
        }
    }

    private func removeFromRadarrQueue(_ item: QueueItem) async {
        do {
            try await RadarrService.shared.removeFromQueue(id: item.id)
            await MainActor.run {
                radarrQueue.removeAll { $0.id == item.id }
            }
        } catch {
            #if DEBUG
            print("Error removing from Radarr queue: \(error)")
            #endif
        }
    }

    private func removeFromSonarrQueue(_ item: QueueItem) async {
        do {
            try await SonarrService.shared.removeFromQueue(id: item.id)
            await MainActor.run {
                sonarrQueue.removeAll { $0.id == item.id }
            }
        } catch {
            #if DEBUG
            print("Error removing from Sonarr queue: \(error)")
            #endif
        }
    }

    private func searchForEpisode(_ episode: Episode) async {
        do {
            try await SonarrService.shared.searchForEpisode(episodeId: episode.id)
        } catch {
            #if DEBUG
            print("Error searching for episode: \(error)")
            #endif
        }
    }

    /// Throttled refresh to prevent rapid API calls
    private func throttledRefresh() async {
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minimumRefreshInterval {
            // Skip refresh if too soon after last one
            return
        }
        await refreshQueue()
    }

    private func refreshQueue() async {
        do {
            let queue = try await SabNZBService.shared.fetchQueue()
            await MainActor.run {
                activeDownloads = queue.downloads
                isQueuePaused = queue.paused
                currentSpeed = queue.speed
                errorMessage = nil
                lastRefreshTime = Date()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load downloads"
            }
        }
    }

    private func refreshHistory() async {
        do {
            let history = try await SabNZBService.shared.fetchHistory()
            await MainActor.run {
                historyDownloads = history
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load history"
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
                await MainActor.run {
                    isQueuePaused.toggle()
                }
            } catch {
                // Handle error silently for now
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
                // Handle error silently for now
            }
        }
    }

    private func deleteDownload(_ download: Download) {
        Task {
            do {
                try await SabNZBService.shared.deleteDownload(id: download.id)
                await MainActor.run {
                    activeDownloads.removeAll { $0.id == download.id }
                }
            } catch {
                // Handle error silently for now
            }
        }
    }

    private func deleteHistoryItem(_ download: HistoryDownload) {
        Task {
            do {
                try await SabNZBService.shared.deleteHistoryItem(id: download.id)
                await MainActor.run {
                    historyDownloads.removeAll { $0.id == download.id }
                }
            } catch {
                // Handle error silently for now
            }
        }
    }

    private func clearAllHistory() {
        Task {
            do {
                try await SabNZBService.shared.clearHistory()
                await MainActor.run {
                    historyDownloads = []
                }
            } catch {
                // Handle error silently for now
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
    let onRemove: () async -> Void

    @State private var isRemoving = false

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
                Button(action: {
                    isRemoving = true
                    Task {
                        await onRemove()
                        isRemoving = false
                    }
                }) {
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
