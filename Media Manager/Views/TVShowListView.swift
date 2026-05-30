import SwiftUI

enum TVShowStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case continuing = "Continuing"
    case ended = "Ended"
    case upcoming = "Upcoming"

    var id: String { rawValue }
}

struct TVShowListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var configuration = ConfigurationManager.shared

    @ObservedObject private var libraryManager = LibraryStateManager.shared
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var statusFilter: TVShowStatusFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedShowIds: Set<Int> = []
    @State private var isRunningBulkAction = false
    @State private var showingBulkDelete = false
    @State private var qualityProfiles: [QualityProfile] = []

    // MARK: - Cached/Memoized State for tvOS Performance
    @State private var cachedFilteredShows: [TVShow] = []
    @State private var lastSearchText: String = ""
    @State private var lastStatusFilter: TVShowStatusFilter = .all
    @State private var lastShowsHash: Int = 0

    /// Deep link TV show ID binding - set by MainTabView for widget navigation
    @Binding var deepLinkTVShowId: Int?

    init(deepLinkTVShowId: Binding<Int?> = .constant(nil)) {
        self._deepLinkTVShowId = deepLinkTVShowId
    }

    private var isConfigured: Bool {
        configuration.isSonarrConfigured
    }

    /// Memoized filtered shows - returns cached result (updated via updateFilteredShows)
    var filteredShows: [TVShow] {
        return cachedFilteredShows
    }

    /// Update cached filtered shows when inputs change
    private func updateFilteredShows() {
        let shows = libraryManager.sortedShows
        let currentHash = shows.hashValue

        // Only recompute if something changed
        guard searchText != lastSearchText || statusFilter != lastStatusFilter || currentHash != lastShowsHash else { return }

        lastSearchText = searchText
        lastStatusFilter = statusFilter
        lastShowsHash = currentHash

        var filtered = shows

        // Apply status filter
        if statusFilter != .all {
            filtered = filtered.filter { $0.status.lowercased() == statusFilter.rawValue.lowercased() }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        cachedFilteredShows = filtered

        // Prefetch images for visible items on tvOS
        #if os(tvOS)
        prefetchVisibleImages()
        #endif
    }

    /// Prefetch images for better scroll performance on tvOS
    private func prefetchVisibleImages() {
        let visibleCount = TVSizing.gridColumns * 3  // Prefetch 3 rows worth
        let urls = cachedFilteredShows.prefix(visibleCount).compactMap { show -> URL? in
            show.images.first(where: { $0.coverType == "poster" })
                .flatMap { $0.remoteUrl.flatMap { URL(string: $0) } }
        }
        ImageCacheManager.shared.prefetch(urls: urls)
    }

    /// Cached grid columns - computed once based on platform
    private var gridColumns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: TVSizing.gridSpacing), count: TVSizing.gridColumns)
        #else
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(), spacing: AppSpacing.md),
                GridItem(.flexible(), spacing: AppSpacing.md)
            ]
        } else {
            return [GridItem(.flexible())]
        }
        #endif
    }

    /// Adaptive horizontal padding: larger on iPad and tvOS
    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return TVSizing.contentPadding
        #else
        return horizontalSizeClass == .regular ? AppSpacing.lg : AppSpacing.md
        #endif
    }

    /// Check if we're on tvOS
    private var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if !isConfigured {
                    PlaceholderView(
                        icon: "gear",
                        title: "Sonarr Not Configured",
                        description: "Go to Settings to configure your Sonarr server URL and API key"
                    )
                } else if libraryManager.isLoadingShows && libraryManager.tvShows.isEmpty {
                    ProgressView()
                        .tint(ColorPalette.primary)
                } else if filteredShows.isEmpty && (!searchText.isEmpty || statusFilter != .all) {
                    VStack(spacing: isTVOS ? AppSpacing.lg : AppSpacing.md) {
                        Image(systemName: statusFilter != .all ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                            .font(.system(size: isTVOS ? 80 : 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No shows found")
                            .font(isTVOS ? AppTypography.title2() : AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text(statusFilter != .all ? "No \(statusFilter.rawValue.lowercased()) shows in library" : "Try a different search term")
                            .font(isTVOS ? AppTypography.body() : AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                        if statusFilter != .all {
                            Button("Clear Filter") {
                                statusFilter = .all
                            }
                            .font(isTVOS ? AppTypography.headline() : AppTypography.body())
                            .foregroundColor(ColorPalette.primary)
                            .padding(.top, AppSpacing.xs)
                        }
                    }
                } else if libraryManager.tvShows.isEmpty {
                    VStack(spacing: isTVOS ? AppSpacing.lg : AppSpacing.md) {
                        Image(systemName: "tv")
                            .font(.system(size: isTVOS ? 80 : 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No TV shows in library")
                            .font(isTVOS ? AppTypography.title2() : AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text("Tap Add to search for shows")
                            .font(isTVOS ? AppTypography.body() : AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: isTVOS ? TVSizing.gridSpacing : AppSpacing.sm) {
                            ForEach(filteredShows) { show in
                                #if os(tvOS)
                                TVShowPosterCard(show: show) {
                                    handleShowTap(show)
                                }
                                .overlay(alignment: .topTrailing) {
                                    selectionBadge(for: show)
                                }
                                #else
                                BookshelfTVShowCard(show: show) {
                                    handleShowTap(show)
                                }
                                .overlay(alignment: .topTrailing) {
                                    selectionBadge(for: show)
                                }
                                #endif
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, isTVOS ? TVSizing.contentPadding : AppSpacing.sm)
                        .padding(.bottom, isTVOS ? TVSizing.contentPadding : AppSpacing.xl)
                    }
                    .refreshable {
                        await libraryManager.loadShows(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("TV Shows")
            .navBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search shows...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.sm) {
                        if !libraryManager.tvShows.isEmpty {
                            Button(isSelectionMode ? "Done" : "Select") {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedShowIds.removeAll()
                                }
                            }
                            .foregroundColor(ColorPalette.secondary)
                        }

                        Menu {
                            ForEach(TVShowStatusFilter.allCases) { filter in
                                Button {
                                    statusFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.rawValue)
                                        if statusFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if statusFilter != .all {
                                    Text(statusFilter.rawValue)
                                        .font(AppTypography.caption1())
                                }
                            }
                            .foregroundColor(statusFilter == .all ? ColorPalette.secondary : ColorPalette.primary)
                        }

                        NavigationLink(destination: AddTVShowView(navigationPath: $navigationPath)) {
                            HStack(spacing: AppSpacing.xxs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Add")
                                    .font(AppTypography.subheadline(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(ColorPalette.primary)
                            .cornerRadius(AppRadius.pill)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            await libraryManager.loadShows(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(ColorPalette.secondary)
                    }
                    .disabled(libraryManager.isLoadingShows)
                }
            }
            .navigationDestination(for: TVShow.self) { show in
                TVShowDetailView(show: show)
            }
            .task {
                if isConfigured && libraryManager.tvShows.isEmpty {
                    await libraryManager.loadShows()
                }
                if isConfigured && qualityProfiles.isEmpty {
                    loadQualityProfiles()
                }
                updateFilteredShows()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredShows()
            }
            .onChange(of: statusFilter) { _, _ in
                updateFilteredShows()
            }
            .onChange(of: libraryManager.tvShows) { _, shows in
                updateFilteredShows()
                // Retry deep link if pending
                if let showId = deepLinkTVShowId,
                   let show = shows.first(where: { $0.id == showId }) {
                    navigationPath.append(show)
                    deepLinkTVShowId = nil
                }
            }
            .onChange(of: deepLinkTVShowId) { _, showId in
                // Handle deep link navigation from widget
                if let showId = showId,
                   let show = libraryManager.tvShows.first(where: { $0.id == showId }) {
                    navigationPath.append(show)
                    deepLinkTVShowId = nil
                }
                // Don't clear deepLinkTVShowId if show not found - retry when data loads
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode && !selectedShowIds.isEmpty {
                    bulkActionBar
                }
            }
            .confirmationDialog("Delete selected shows?", isPresented: $showingBulkDelete, titleVisibility: .visible) {
                Button("Remove from Sonarr Only", role: .destructive) {
                    runBulkDelete(deleteFiles: false)
                }
                Button("Remove and Delete Files", role: .destructive) {
                    runBulkDelete(deleteFiles: true)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    @ViewBuilder
    private func selectionBadge(for show: TVShow) -> some View {
        if isSelectionMode {
            Image(systemName: selectedShowIds.contains(show.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(selectedShowIds.contains(show.id) ? ColorPalette.primary : ColorPalette.textSecondaryDark)
                .padding(AppSpacing.sm)
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(selectedShowIds.count) selected")
                .font(AppTypography.caption1(.semibold))
                .foregroundColor(ColorPalette.textSecondaryDark)

            Spacer()

            Button { runBulkMonitoring(monitored: true) } label: {
                Image(systemName: "eye.fill")
            }
            Button { runBulkMonitoring(monitored: false) } label: {
                Image(systemName: "eye.slash.fill")
            }
            Button { runBulkSearch() } label: {
                Image(systemName: "magnifyingglass")
            }
            Menu {
                ForEach(qualityProfiles) { profile in
                    Button(profile.name) {
                        runBulkQualityChange(profileId: profile.id)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .disabled(qualityProfiles.isEmpty)
            Button(role: .destructive) { showingBulkDelete = true } label: {
                Image(systemName: "trash")
            }
        }
        .font(AppTypography.body(.semibold))
        .foregroundColor(ColorPalette.primary)
        .padding(AppSpacing.md)
        .background(.ultraThinMaterial)
        .disabled(isRunningBulkAction)
    }

    private func handleShowTap(_ show: TVShow) {
        if isSelectionMode {
            if selectedShowIds.contains(show.id) {
                selectedShowIds.remove(show.id)
            } else {
                selectedShowIds.insert(show.id)
            }
        } else {
            navigationPath.append(show)
        }
    }

    private func selectedShows() -> [TVShow] {
        libraryManager.tvShows.filter { selectedShowIds.contains($0.id) }
    }

    private func loadQualityProfiles() {
        Task {
            do {
                let profiles = try await SonarrService.shared.fetchQualityProfiles()
                await MainActor.run {
                    qualityProfiles = profiles
                }
            } catch {
                #if DEBUG
                print("Error loading Sonarr quality profiles: \(error)")
                #endif
            }
        }
    }

    private func runBulkMonitoring(monitored: Bool) {
        isRunningBulkAction = true
        Task {
            do {
                for show in selectedShows() {
                    try await SonarrService.shared.updateShowMonitoring(seriesId: show.id, monitored: monitored)
                }
                await libraryManager.loadShows(forceRefresh: true)
                await MainActor.run {
                    selectedShowIds.removeAll()
                    isSelectionMode = false
                    isRunningBulkAction = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunningBulkAction = false
                }
            }
        }
    }

    private func runBulkSearch() {
        isRunningBulkAction = true
        Task {
            do {
                for show in selectedShows() {
                    try await SonarrService.shared.searchForShow(seriesId: show.id)
                }
                await MainActor.run {
                    selectedShowIds.removeAll()
                    isSelectionMode = false
                    isRunningBulkAction = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunningBulkAction = false
                }
            }
        }
    }

    private func runBulkQualityChange(profileId: Int) {
        isRunningBulkAction = true
        Task {
            do {
                for show in selectedShows() {
                    var updated = show
                    updated.qualityProfileId = profileId
                    try await SonarrService.shared.updateShow(show: updated)
                }
                await libraryManager.loadShows(forceRefresh: true)
                await MainActor.run {
                    selectedShowIds.removeAll()
                    isSelectionMode = false
                    isRunningBulkAction = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunningBulkAction = false
                }
            }
        }
    }

    private func runBulkDelete(deleteFiles: Bool) {
        isRunningBulkAction = true
        Task {
            do {
                for show in selectedShows() {
                    try await SonarrService.shared.deleteShow(id: show.id, deleteFiles: deleteFiles)
                }
                await libraryManager.loadShows(forceRefresh: true)
                await MainActor.run {
                    selectedShowIds.removeAll()
                    isSelectionMode = false
                    isRunningBulkAction = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunningBulkAction = false
                }
            }
        }
    }
}

#Preview {
    TVShowListView()
        .preferredColorScheme(.dark)
}
