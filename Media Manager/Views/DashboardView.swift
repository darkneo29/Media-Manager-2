import SwiftUI

struct DashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var configuration = ConfigurationManager.shared
    @ObservedObject private var libraryState = LibraryStateManager.shared
    @ObservedObject private var releaseRadar = ReleaseRadarService.shared
    @State private var trendingMovies: [TrendingMovie] = []
    @State private var trendingTVShows: [TrendingTVShow] = []
    @State private var isInitialLoad = true  // Only true for very first load
    @State private var errorMessage: String?
    @State private var followedShowEventLabels: [Int: String] = [:]

    // Navigation state
    @State private var navigationPath = NavigationPath()

    // Sheet state
    @State private var selectedTrendingMovie: TrendingMovie?
    @State private var selectedTrendingShow: TrendingTVShow?

    // Track if initial data has been loaded this session
    @State private var hasLoadedInitialData = false

    /// Whether we have any data to display (cached or fresh)
    private var hasDataToDisplay: Bool {
        !trendingMovies.isEmpty || !trendingTVShows.isEmpty ||
        !libraryState.movies.isEmpty || !libraryState.tvShows.isEmpty
    }

    /// Show loading spinner only on first load with no cached data
    private var shouldShowLoading: Bool {
        isInitialLoad && !hasDataToDisplay
    }

    private var isTMDBConfigured: Bool {
        configuration.isTMDBConfigured
    }

    private var dashboardErrorMessage: String? {
        errorMessage ?? libraryState.moviesErrorMessage ?? libraryState.showsErrorMessage
    }

    /// Grid columns for iPad: 4 columns to display more content
    private var iPadGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4)
    }

    /// Grid columns for tvOS: 6 columns for larger screen
    private var tvOSGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: TVSizing.gridSpacing), count: TVSizing.gridColumns)
    }

    /// Adaptive horizontal padding: larger on iPad and tvOS
    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return TVSizing.contentPadding
        #else
        return horizontalSizeClass == .regular ? AppSpacing.lg : AppSpacing.md
        #endif
    }

    /// Check if we're on iPad
    private var isIPad: Bool {
        horizontalSizeClass == .regular
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

                if !isTMDBConfigured {
                    PlaceholderView(
                        icon: "gear",
                        title: "TMDB Not Configured",
                        description: "Go to Settings to configure your TMDB API token for trending content"
                    )
                } else if shouldShowLoading {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.primary))
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .font(AppTypography.subheadline())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                } else if let message = dashboardErrorMessage, !hasDataToDisplay {
                    PlaceholderView(
                        icon: "wifi.exclamationmark",
                        title: "Couldn't Load Home",
                        description: message,
                        action: PlaceholderView.ActionConfig(
                            title: "Try Again",
                            icon: "arrow.clockwise",
                            handler: {
                                Task {
                                    await loadData(forceRefresh: true, forceWidgetReload: true)
                                    hasLoadedInitialData = true
                                }
                            }
                        )
                    )
                } else {
                    #if os(tvOS)
                    // tvOS: Fixed header with scrollable content below
                    VStack(spacing: 0) {
                        // Fixed navigation bar
                        tvOSNavigationBar

                        ScrollView {
                            VStack(spacing: TVSizing.sectionSpacing) {
                                ServerHealthWidget(showHeader: true, onTap: {
                                    navigationPath.append("server")
                                })
                                .padding(.horizontal, TVSizing.contentPadding)

                                if shouldShowReleaseRadarSection {
                                    releaseRadarSection
                                }

                                // Trending Movies Section
                                if !trendingMovies.isEmpty {
                                    DashboardSection(
                                        title: "Trending Movies",
                                        subtitle: "Popular this week"
                                    ) {
                                        trendingMoviesSection
                                    }
                                }

                                // Trending TV Shows Section
                                if !trendingTVShows.isEmpty {
                                    DashboardSection(
                                        title: "Trending TV Shows",
                                        subtitle: "What everyone's watching"
                                    ) {
                                        trendingTVShowsSection
                                    }
                                }

                                // Coming Soon Section
                                if !comingSoonItems.isEmpty {
                                    DashboardSection(
                                        title: "Coming Soon",
                                        subtitle: "Upcoming releases"
                                    ) {
                                        comingSoonSection
                                    }
                                }

                                // Recently Added Section
                                if !recentlyAddedItems.isEmpty {
                                    DashboardSection(
                                        title: "Recently Added",
                                        subtitle: "Latest in your library"
                                    ) {
                                        recentlyAddedSection
                                    }
                                }
                            }
                            .padding(.vertical, AppSpacing.md)
                        }
                    }
                    #else
                    // iOS/iPadOS: Standard scroll view
                    ScrollView {
                        VStack(spacing: TVSizing.sectionSpacing) {
                            // Server Health Widget (self-hides if not configured or connection fails)
                            ServerHealthWidget(showHeader: true, onTap: {
                                navigationPath.append("server")
                            })
                            .padding(.horizontal, AppSpacing.md)

                            if shouldShowReleaseRadarSection {
                                releaseRadarSection
                            }

                            // Trending Movies Section
                            if !trendingMovies.isEmpty {
                                DashboardSection(
                                    title: "Trending Movies",
                                    subtitle: "Popular this week"
                                ) {
                                    trendingMoviesSection
                                }
                            }

                            // Trending TV Shows Section
                            if !trendingTVShows.isEmpty {
                                DashboardSection(
                                    title: "Trending TV Shows",
                                    subtitle: "What everyone's watching"
                                ) {
                                    trendingTVShowsSection
                                }
                            }

                            // Coming Soon Section
                            if !comingSoonItems.isEmpty {
                                DashboardSection(
                                    title: "Coming Soon",
                                    subtitle: "Upcoming releases"
                                ) {
                                    comingSoonSection
                                }
                            }

                            // Recently Added Section
                            if !recentlyAddedItems.isEmpty {
                                DashboardSection(
                                    title: "Recently Added",
                                    subtitle: "Latest in your library"
                                ) {
                                    recentlyAddedSection
                                }
                            }
                        }
                        .padding(.vertical, AppSpacing.md)
                    }
                    .refreshable {
                        await loadData(forceRefresh: true, forceWidgetReload: true)
                    }
                    #endif
                }
            }
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorPalette.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
            .navigationDestination(for: TVShow.self) { show in
                TVShowDetailView(show: show)
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "server" {
                    ServerView(isEmbedded: true)
                }
            }
        }
        .task {
            // Only load data once on initial app launch
            if isTMDBConfigured && !hasLoadedInitialData {
                await loadData()
                hasLoadedInitialData = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && hasLoadedInitialData {
                // Refresh when app returns from background (not on initial launch)
                Task {
                    await loadData(forceRefresh: true)
                }
            }
        }
        .onChange(of: releaseRadar.followedShowIds) { _, _ in
            Task {
                await loadFollowedShowEventLabels()
            }
        }
        .sheet(item: $selectedTrendingMovie) { movie in
            QuickAddMovieSheet(movie: movie) {
                // Library state is updated optimistically by QuickAddSheet
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $selectedTrendingShow) { show in
            QuickAddTVShowSheet(show: show) {
                // Library state is updated optimistically by QuickAddSheet
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Library Lookup (Using Shared State)

    /// Check if a trending movie is already in the library
    private func isMovieInLibrary(_ movie: TrendingMovie) -> Bool {
        libraryState.isMovieInLibrary(tmdbId: movie.id)
    }

    /// Check if a trending TV show is already in the library
    private func isShowInLibrary(_ show: TrendingTVShow) -> Bool {
        libraryState.isShowInLibrary(tvdbId: show.tvdbId, name: show.name, year: show.year)
    }

    // MARK: - Computed Properties

    private struct ReleaseRadarItem: Identifiable {
        let event: CalendarEvent
        let badgeText: String
        let subtitle: String
        let isFollowed: Bool

        var id: UUID { event.id }
    }

    private var releaseRadarWindowEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let upperBound = calendar.date(byAdding: .day, value: 30, to: startOfToday) ?? startOfToday

        return CalendarEventBuilder.allEvents(movies: libraryState.movies, tvShows: libraryState.tvShows)
            .filter { $0.date >= startOfToday && $0.date <= upperBound }
            .sorted(by: releaseRadarSort)
    }

    private var releaseRadarItems: [ReleaseRadarItem] {
        return releaseRadar.filteredEvents(
            releaseRadarWindowEvents
        )
        .prefix(15)
        .map { event in
            let isFollowed = releaseRadar.isFollowing(event: event)
            let subtitle = "\(event.relativeDateLabel) • \(radarTypeLabel(for: event))"
            let badgeText = event.isNowAvailable ? "Now" : (isFollowed ? "Following" : event.radarBadgeText)

            return ReleaseRadarItem(
                event: event,
                badgeText: badgeText,
                subtitle: subtitle,
                isFollowed: isFollowed
            )
        }
    }

    private var shouldShowReleaseRadarSection: Bool {
        !releaseRadarWindowEvents.isEmpty ||
        releaseRadar.hasCustomFilters ||
        !releaseRadar.followedMovieIds.isEmpty ||
        !releaseRadar.followedShowIds.isEmpty
    }

    private var releaseRadarSubtitle: String {
        let followedCount = releaseRadarWindowEvents.filter(releaseRadar.isFollowing(event:)).count

        if releaseRadarItems.isEmpty && releaseRadar.hasCustomFilters && !releaseRadarWindowEvents.isEmpty {
            return "Your current filters are hiding everything in the next 30 days"
        }

        if followedCount > 0 {
            return "\(followedCount) followed release\(followedCount == 1 ? "" : "s") in the next 30 days"
        }

        return "Upcoming releases from your monitored library"
    }

    private var comingSoonItems: [(id: String, title: String, subtitle: String, posterURL: URL?, isMovie: Bool)] {
        var items: [(id: String, title: String, subtitle: String, posterURL: URL?, isMovie: Bool)] = []

        // Coming soon movies from shared state
        for movie in libraryState.comingSoonMovies.prefix(10) {
            let posterURL = movie.images.first(where: { $0.coverType == "poster" })
                .flatMap { $0.remoteUrl.flatMap { URL(string: $0) } }
            items.append((
                id: "movie-\(movie.id)",
                title: movie.title,
                subtitle: String(movie.year),
                posterURL: posterURL,
                isMovie: true
            ))
        }

        // Coming soon shows from shared state
        for show in libraryState.comingSoonShows.prefix(10) {
            let posterURL = show.images.first(where: { $0.coverType == "poster" })
                .flatMap { $0.remoteUrl.flatMap { URL(string: $0) } }
            items.append((
                id: "show-\(show.id)",
                title: show.title,
                subtitle: show.network ?? String(show.year),
                posterURL: posterURL,
                isMovie: false
            ))
        }

        return items
    }

    private var recentlyAddedItems: [(id: String, title: String, subtitle: String, posterURL: URL?, isMovie: Bool)] {
        var items: [(id: String, title: String, subtitle: String, posterURL: URL?, addedDate: Date?, isMovie: Bool)] = []

        // Recent movies from shared state
        for movie in libraryState.movies {
            let posterURL = movie.images.first(where: { $0.coverType == "poster" })
                .flatMap { $0.remoteUrl.flatMap { URL(string: $0) } }
            items.append((
                id: "movie-\(movie.id)",
                title: movie.title,
                subtitle: String(movie.year),
                posterURL: posterURL,
                addedDate: movie.addedDate,
                isMovie: true
            ))
        }

        // Recent shows from shared state
        for show in libraryState.tvShows {
            let posterURL = show.images.first(where: { $0.coverType == "poster" })
                .flatMap { $0.remoteUrl.flatMap { URL(string: $0) } }
            items.append((
                id: "show-\(show.id)",
                title: show.title,
                subtitle: show.network ?? String(show.year),
                posterURL: posterURL,
                addedDate: show.addedDate,
                isMovie: false
            ))
        }

        // Sort by added date (most recent first) and take top 15
        let sorted = items.sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
        return sorted.prefix(15).map { (id: $0.id, title: $0.title, subtitle: $0.subtitle, posterURL: $0.posterURL, isMovie: $0.isMovie) }
    }

    private var releaseRadarSection: some View {
        VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.lg : AppSpacing.sm) {
            VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.xs : AppSpacing.xxs) {
                Text("Release Radar")
                    .font(TVSizing.isTV ? AppTypography.title1() : AppTypography.title3())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Text(releaseRadarSubtitle)
                    .font(TVSizing.isTV ? AppTypography.body() : AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, TVSizing.contentPadding)

            ReleaseRadarFilterBar(enabledFilters: releaseRadar.enabledFilters) { filter in
                toggleReleaseRadarFilter(filter)
            }

            Group {
                if releaseRadarItems.isEmpty {
                    releaseRadarEmptyState
                } else {
                    #if os(tvOS)
                    LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                        ForEach(releaseRadarItems.prefix(18)) { item in
                            releaseRadarCard(item)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    #else
                    if isIPad {
                        LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                            ForEach(releaseRadarItems.prefix(12)) { item in
                                releaseRadarCard(item)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.md) {
                                ForEach(releaseRadarItems) { item in
                                    releaseRadarCard(item)
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                    }
                    #endif
                }
            }
        }
    }

    private var releaseRadarEmptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label {
                Text(releaseRadarEmptyTitle)
                    .font(TVSizing.isTV ? AppTypography.title3() : AppTypography.headline())
                    .foregroundColor(ColorPalette.textPrimaryDark)
            } icon: {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundColor(ColorPalette.secondary)
            }

            Text(releaseRadarEmptyDescription)
                .font(TVSizing.isTV ? AppTypography.body() : AppTypography.subheadline())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .fixedSize(horizontal: false, vertical: true)

            if releaseRadar.hasCustomFilters {
                Button {
                    showAllReleaseRadarFilters()
                } label: {
                    Label("Show All Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .secondaryButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TVSizing.isTV ? AppSpacing.lg : AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(ColorPalette.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
        .padding(.horizontal, horizontalPadding)
    }

    private var releaseRadarEmptyTitle: String {
        if releaseRadar.hasCustomFilters {
            return "No releases match the current filters"
        }

        if !releaseRadar.followedMovieIds.isEmpty || !releaseRadar.followedShowIds.isEmpty {
            return "No followed releases in the next 30 days"
        }

        return "No upcoming releases in the next 30 days"
    }

    private var releaseRadarEmptyDescription: String {
        if releaseRadar.hasCustomFilters {
            return "The Home screen filters are hiding every upcoming release right now. Reset the filters to bring Release Radar back immediately."
        }

        if !releaseRadar.followedMovieIds.isEmpty || !releaseRadar.followedShowIds.isEmpty {
            return "Your followed titles do not have a release or episode date in the next 30 days yet. They will appear here automatically when dates are available."
        }

        return "Release Radar will populate here as upcoming movie and TV events enter the next 30 days."
    }

    // MARK: - tvOS Navigation Bar

    #if os(tvOS)
    private var tvOSNavigationBar: some View {
        HStack {
            Text("Home")
                .font(AppTypography.title2(.bold))
                .foregroundColor(ColorPalette.textPrimaryDark)
            Spacer()
            Button {
                Task {
                    await loadData(forceRefresh: true, forceWidgetReload: true)
                    hasLoadedInitialData = true
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 64, height: 48)
            }
            .buttonStyle(TVCardButtonStyle())
            .disabled(shouldShowLoading)
        }
        .padding(.horizontal, TVSizing.contentPadding)
        .padding(.vertical, AppSpacing.md)
        .background(ColorPalette.backgroundDark)
    }
    #endif

    // MARK: - Section Views

    private var trendingMoviesSection: some View {
        Group {
            #if os(tvOS)
            // tvOS: Large grid layout
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(trendingMovies.prefix(18)) { movie in
                    trendingMovieCard(movie)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                // iPad: Grid layout
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(trendingMovies.prefix(12)) { movie in
                        trendingMovieCard(movie)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(trendingMovies.prefix(15)) { movie in
                            trendingMovieCard(movie)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    private func trendingMovieCard(_ movie: TrendingMovie) -> some View {
        let inLibrary = isMovieInLibrary(movie)
        return DashboardCard(
            imageURL: movie.posterURL,
            title: movie.title,
            subtitle: movie.year.map { String($0) },
            isInLibrary: inLibrary
        ) {
            if inLibrary {
                if let libraryMovie = libraryState.findMovie(byTmdbId: movie.id) {
                    navigationPath.append(libraryMovie)
                }
            } else {
                selectedTrendingMovie = movie
            }
        }
    }

    private var trendingTVShowsSection: some View {
        Group {
            #if os(tvOS)
            // tvOS: Large grid layout
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(trendingTVShows.prefix(18)) { show in
                    trendingTVShowCard(show)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                // iPad: Grid layout
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(trendingTVShows.prefix(12)) { show in
                        trendingTVShowCard(show)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(trendingTVShows.prefix(15)) { show in
                            trendingTVShowCard(show)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    private func trendingTVShowCard(_ show: TrendingTVShow) -> some View {
        let inLibrary = isShowInLibrary(show)
        return DashboardCard(
            imageURL: show.posterURL,
            title: show.name,
            subtitle: show.year.map { String($0) },
            isInLibrary: inLibrary
        ) {
            if inLibrary {
                if let libraryShow = libraryState.findShow(tvdbId: show.tvdbId, name: show.name, year: show.year) {
                    navigationPath.append(libraryShow)
                }
            } else {
                selectedTrendingShow = show
            }
        }
    }

    private var comingSoonSection: some View {
        Group {
            #if os(tvOS)
            // tvOS: Large grid layout
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(comingSoonItems.prefix(18), id: \.id) { item in
                    comingSoonCard(item)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                // iPad: Grid layout
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(comingSoonItems.prefix(12), id: \.id) { item in
                        comingSoonCard(item)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(comingSoonItems, id: \.id) { item in
                            comingSoonCard(item)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    private func comingSoonCard(_ item: (id: String, title: String, subtitle: String, posterURL: URL?, isMovie: Bool)) -> some View {
        DashboardCard(
            imageURL: item.posterURL,
            title: item.title,
            subtitle: item.subtitle,
            badgeText: item.isMovie ? "Movie" : "TV"
        ) {
            navigateToLibraryItem(id: item.id, isMovie: item.isMovie)
        }
    }

    private var recentlyAddedSection: some View {
        Group {
            #if os(tvOS)
            // tvOS: Large grid layout
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(recentlyAddedItems.prefix(18), id: \.id) { item in
                    recentlyAddedCard(item)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                // iPad: Grid layout
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(recentlyAddedItems.prefix(12), id: \.id) { item in
                        recentlyAddedCard(item)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                // iPhone: Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(recentlyAddedItems, id: \.id) { item in
                            recentlyAddedCard(item)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    private func recentlyAddedCard(_ item: (id: String, title: String, subtitle: String, posterURL: URL?, isMovie: Bool)) -> some View {
        DashboardCard(
            imageURL: item.posterURL,
            title: item.title,
            subtitle: item.subtitle,
            badgeText: item.isMovie ? "Movie" : "TV"
        ) {
            navigateToLibraryItem(id: item.id, isMovie: item.isMovie)
        }
    }

    private func releaseRadarCard(_ item: ReleaseRadarItem) -> some View {
        DashboardCard(
            imageURL: item.event.posterURL,
            title: item.event.title,
            subtitle: item.subtitle,
            badgeText: item.badgeText
        ) {
            navigateToDetail(for: item.event)
        }
    }

    // MARK: - Navigation Helper

    /// Navigate to a library item's detail view
    private func navigateToLibraryItem(id: String, isMovie: Bool) {
        // Extract numeric ID from string like "movie-123" or "show-456"
        let numericId = id.components(separatedBy: "-").last.flatMap { Int($0) }
        guard let itemId = numericId else { return }

        if isMovie {
            if let movie = libraryState.movies.first(where: { $0.id == itemId }) {
                navigationPath.append(movie)
            }
        } else {
            if let show = libraryState.tvShows.first(where: { $0.id == itemId }) {
                navigationPath.append(show)
            }
        }
    }

    private func navigateToDetail(for event: CalendarEvent) {
        switch event.source {
        case .movie(let movie):
            navigationPath.append(movie)
        case .tvShow(let show):
            navigationPath.append(show)
        }
    }

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false, forceWidgetReload: Bool = false) async {
        errorMessage = nil

        // Fetch new data in background (doesn't block UI if we have cached data)
        await withTaskGroup(of: Void.self) { group in
            // Load trending from TMDB (uses cache unless forceRefresh)
            group.addTask { await loadTrendingData(forceRefresh: forceRefresh) }
            // Load library from shared state (uses cache unless forceRefresh)
            group.addTask { await libraryState.loadAll(forceRefresh: forceRefresh) }
        }

        await loadFollowedShowEventLabels(forceRefresh: forceRefresh)

        // Update widget data with upcoming releases
        updateWidgetData(forceReload: forceWidgetReload)

        // Mark initial load complete (stops showing loading spinner)
        if isInitialLoad {
            isInitialLoad = false
        }
    }

    /// Update widget with upcoming releases from library
    private func updateWidgetData(forceReload: Bool = false) {
        let hasServers = ConfigurationManager.shared.isRadarrConfigured || ConfigurationManager.shared.isSonarrConfigured
        WidgetDataService.shared.updateWidgetData(
            movies: libraryState.movies,
            tvShows: libraryState.tvShows,
            isConfigured: hasServers,
            forceReload: forceReload
        )
    }

    private func loadTrendingData(forceRefresh: Bool = false) async {
        do {
            async let movies = TMDBService.shared.fetchTrendingMovies(forceRefresh: forceRefresh)
            async let shows = TMDBService.shared.fetchTrendingTVShows(forceRefresh: forceRefresh)

            let (fetchedMovies, fetchedShows) = try await (movies, shows)

            // Update state atomically only when new data is ready
            // This prevents UI flicker and maintains smooth experience
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    trendingMovies = fetchedMovies
                    trendingTVShows = fetchedShows
                }
            }
        } catch {
            // Only show error if we have no data at all
            await MainActor.run {
                if trendingMovies.isEmpty && trendingTVShows.isEmpty {
                    errorMessage = "Failed to load trending content"
                }
            }
        }
    }

    private func toggleReleaseRadarFilter(_ filter: ReleaseRadarEventFilter) {
        releaseRadar.toggleFilter(filter)
        updateWidgetData(forceReload: true)
    }

    private func showAllReleaseRadarFilters() {
        releaseRadar.enableAllFilters()
        updateWidgetData(forceReload: true)
    }

    private func releaseRadarSort(lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        let lhsFollowed = releaseRadar.isFollowing(event: lhs)
        let rhsFollowed = releaseRadar.isFollowing(event: rhs)

        if lhsFollowed != rhsFollowed {
            return lhsFollowed
        }

        if lhs.isNowAvailable != rhs.isNowAvailable {
            return lhs.isNowAvailable
        }

        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }

        return lhs.title < rhs.title
    }

    private func radarTypeLabel(for event: CalendarEvent) -> String {
        switch event.source {
        case .movie:
            return event.isNowAvailable ? "Now Available" : event.typeLabel
        case .tvShow(let show):
            return followedShowEventLabels[show.id] ?? event.typeLabel
        }
    }

    private func loadFollowedShowEventLabels(forceRefresh: Bool = false) async {
        let followedIds = releaseRadar.followedShowIds
        let followedShows = libraryState.tvShows.filter {
            followedIds.contains($0.id) && $0.nextAiring != nil
        }

        guard !followedShows.isEmpty else {
            followedShowEventLabels = [:]
            return
        }

        var labels: [Int: String] = [:]

        await withTaskGroup(of: (Int, String?).self) { group in
            for show in followedShows {
                group.addTask {
                    do {
                        let episodes = try await SonarrService.shared.fetchEpisodes(
                            seriesId: show.id,
                            forceRefresh: forceRefresh
                        )
                        return (show.id, Self.releaseRadarLabel(for: episodes))
                    } catch {
                        return (show.id, nil)
                    }
                }
            }

            for await (showId, label) in group {
                if let label {
                    labels[showId] = label
                }
            }
        }

        followedShowEventLabels = labels
    }

    nonisolated private static func releaseRadarLabel(for episodes: [Episode]) -> String {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let upcomingEpisodes = episodes
            .compactMap { episode -> (Episode, Date)? in
                guard let airDateUtc = episode.airDateUtc else { return nil }
                let airDate = formatterWithFractionalSeconds.date(from: airDateUtc)
                    ?? formatter.date(from: airDateUtc)
                guard let airDate, airDate >= Date() else { return nil }
                return (episode, airDate)
            }
            .sorted { $0.1 < $1.1 }

        guard let nextEpisode = upcomingEpisodes.first?.0 else {
            return "New Episode"
        }

        let seasonEpisodes = episodes.filter { $0.seasonNumber == nextEpisode.seasonNumber }
        let highestEpisodeNumber = seasonEpisodes.map(\.episodeNumber).max() ?? nextEpisode.episodeNumber

        if nextEpisode.episodeNumber == 1 {
            return nextEpisode.seasonNumber <= 1 ? "Series Premiere" : "Season Premiere"
        }

        if nextEpisode.episodeNumber == highestEpisodeNumber {
            return "Season Finale"
        }

        return "New Episode"
    }
}

// MARK: - Dashboard Section

struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.lg : AppSpacing.sm) {
            // Header
            VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.xs : AppSpacing.xxs) {
                Text(title)
                    .font(TVSizing.isTV ? AppTypography.title1() : AppTypography.title3())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Text(subtitle)
                    .font(TVSizing.isTV ? AppTypography.body() : AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, TVSizing.contentPadding)

            // Content
            content
        }
    }
}

// MARK: - Dashboard Card

struct DashboardCard: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    var badgeText: String? = nil
    var isInLibrary: Bool = false
    let onTap: () -> Void

    @Environment(\.isFocused) private var isFocused

    private var posterWidth: CGFloat { TVSizing.posterWidth }
    private var posterHeight: CGFloat { TVSizing.posterHeight }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs) {
                // Poster with optional badge or checkmark
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: imageURL, width: posterWidth, height: posterHeight)
                        .cornerRadius(TVSizing.isTV ? AppRadius.lg : AppRadius.md)
                        #if os(tvOS)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg)
                                .stroke(
                                    isFocused ? ColorPalette.primary : Color.clear,
                                    lineWidth: 4
                                )
                        )
                        #endif

                    if isInLibrary {
                        // Green checkmark for items in library
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: TVSizing.isTV ? 32 : 24))
                            .foregroundColor(ColorPalette.success)
                            .background(
                                Circle()
                                    .fill(ColorPalette.backgroundDark)
                                    .frame(
                                        width: TVSizing.isTV ? 28 : 22,
                                        height: TVSizing.isTV ? 28 : 22
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
                    } else if let badge = badgeText {
                        Text(badge)
                            .font(TVSizing.isTV ? AppTypography.caption1(.semibold) : AppTypography.caption2(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
                            .padding(.vertical, TVSizing.isTV ? 4 : 2)
                            .background(ColorPalette.primary.opacity(0.9))
                            .cornerRadius(AppRadius.sm)
                            .padding(TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
                    }
                }

                // Title and subtitle
                VStack(alignment: .leading, spacing: TVSizing.isTV ? 4 : 2) {
                    Text(title)
                        .font(TVSizing.isTV ? AppTypography.body(.medium) : AppTypography.caption1(.medium))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(TVSizing.isTV ? 2 : 1)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(TVSizing.isTV ? AppTypography.subheadline() : AppTypography.caption2())
                            .foregroundColor(ColorPalette.textMutedDark)
                            .lineLimit(1)
                    }
                }
                .frame(width: posterWidth, alignment: .leading)
            }
        }
        .buttonStyle(DashboardCardButtonStyle())
    }
}

/// Button style for dashboard cards with focus effects
/// Optimized for tvOS performance with reduced shadow complexity and longer animations
struct DashboardCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            #if os(tvOS)
            .scaleEffect(isFocused ? TVSizing.focusScale : (configuration.isPressed ? 0.95 : 1.0))
            .shadow(
                color: isFocused ? ColorPalette.primary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0,
                x: 0,
                y: isFocused ? 6 : 0  // Reduced y-offset for simpler shadow
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
            #else
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            #endif
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    DashboardView()
        .preferredColorScheme(.dark)
}
