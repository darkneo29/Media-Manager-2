import SwiftUI

struct DiscoverView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var configuration = ConfigurationManager.shared

    @ObservedObject private var libraryState = LibraryStateManager.shared

    // Section data
    @State private var popularMovies: [TrendingMovie] = []
    @State private var popularTVShows: [TrendingTVShow] = []
    @State private var topRatedMovies: [TrendingMovie] = []
    @State private var topRatedTVShows: [TrendingTVShow] = []
    @State private var nowPlayingMovies: [TrendingMovie] = []
    @State private var onTheAirTVShows: [TrendingTVShow] = []
    @State private var upcomingMovies: [TrendingMovie] = []
    @State private var airingTodayTVShows: [TrendingTVShow] = []

    @State private var isInitialLoad = true
    @State private var errorMessage: String?

    // Navigation state
    @State private var navigationPath = NavigationPath()

    // Sheet state
    @State private var selectedMovie: TrendingMovie?
    @State private var selectedTVShow: TrendingTVShow?

    // Track if initial data has been loaded this session
    @State private var hasLoadedInitialData = false

    private var hasDataToDisplay: Bool {
        !popularMovies.isEmpty || !popularTVShows.isEmpty ||
        !topRatedMovies.isEmpty || !topRatedTVShows.isEmpty ||
        !nowPlayingMovies.isEmpty || !onTheAirTVShows.isEmpty ||
        !upcomingMovies.isEmpty || !airingTodayTVShows.isEmpty
    }

    private var shouldShowLoading: Bool {
        isInitialLoad && !hasDataToDisplay
    }

    private var isTMDBConfigured: Bool {
        configuration.isTMDBConfigured
    }

    private var iPadGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4)
    }

    private var tvOSGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: TVSizing.gridSpacing), count: TVSizing.gridColumns)
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return TVSizing.contentPadding
        #else
        return horizontalSizeClass == .regular ? AppSpacing.lg : AppSpacing.md
        #endif
    }

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if !isTMDBConfigured {
                    PlaceholderView(
                        icon: "gear",
                        title: "TMDB Not Configured",
                        description: "Go to Settings to configure your TMDB API token for Discover content"
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
                } else if let errorMessage, !hasDataToDisplay {
                    PlaceholderView(
                        icon: "wifi.exclamationmark",
                        title: "Couldn't Load Discover",
                        description: errorMessage,
                        action: PlaceholderView.ActionConfig(
                            title: "Try Again",
                            icon: "arrow.clockwise",
                            handler: {
                                Task {
                                    await loadData(forceRefresh: true)
                                    hasLoadedInitialData = true
                                }
                            }
                        )
                    )
                } else {
                    #if os(tvOS)
                    VStack(spacing: 0) {
                        tvOSNavigationBar

                        ScrollView {
                            VStack(spacing: TVSizing.sectionSpacing) {
                                discoverSections
                            }
                            .padding(.vertical, AppSpacing.md)
                        }
                    }
                    #else
                    ScrollView {
                        VStack(spacing: TVSizing.sectionSpacing) {
                            discoverSections
                        }
                        .padding(.vertical, AppSpacing.md)
                    }
                    .refreshable {
                        await loadData(forceRefresh: true)
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
        }
        .task {
            if isTMDBConfigured && !hasLoadedInitialData {
                await loadData()
                hasLoadedInitialData = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && hasLoadedInitialData {
                Task {
                    await loadData(forceRefresh: true)
                }
            }
        }
        .sheet(item: $selectedMovie) { movie in
            QuickAddMovieSheet(movie: movie) {
                // Library state is updated optimistically by QuickAddSheet
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $selectedTVShow) { show in
            QuickAddTVShowSheet(show: show) {
                // Library state is updated optimistically by QuickAddSheet
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var discoverSections: some View {
        // 1. Popular Movies
        if !popularMovies.isEmpty {
            DashboardSection(title: "Popular Movies", subtitle: "What everyone's watching") {
                movieSection(popularMovies)
            }
        }

        // 2. Popular TV Shows
        if !popularTVShows.isEmpty {
            DashboardSection(title: "Popular TV Shows", subtitle: "Trending series right now") {
                tvShowSection(popularTVShows)
            }
        }

        // 3. Top Rated Movies
        if !topRatedMovies.isEmpty {
            DashboardSection(title: "Top Rated Movies", subtitle: "Highest rated of all time") {
                movieSection(topRatedMovies)
            }
        }

        // 4. Top Rated TV Shows
        if !topRatedTVShows.isEmpty {
            DashboardSection(title: "Top Rated TV Shows", subtitle: "The best series ever made") {
                tvShowSection(topRatedTVShows)
            }
        }

        // 5. Now Playing
        if !nowPlayingMovies.isEmpty {
            DashboardSection(title: "Now Playing", subtitle: "Currently in theaters") {
                movieSection(nowPlayingMovies)
            }
        }

        // 6. On The Air
        if !onTheAirTVShows.isEmpty {
            DashboardSection(title: "On The Air", subtitle: "Currently airing series") {
                tvShowSection(onTheAirTVShows)
            }
        }

        // 7. Upcoming Movies
        if !upcomingMovies.isEmpty {
            DashboardSection(title: "Upcoming Movies", subtitle: "Coming soon to theaters") {
                movieSection(upcomingMovies)
            }
        }

        // 8. Airing Today
        if !airingTodayTVShows.isEmpty {
            DashboardSection(title: "Airing Today", subtitle: "New episodes today") {
                tvShowSection(airingTodayTVShows)
            }
        }
    }

    // MARK: - Adaptive Section Builders

    private func movieSection(_ movies: [TrendingMovie]) -> some View {
        Group {
            #if os(tvOS)
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(movies.prefix(18)) { movie in
                    movieCard(movie)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(movies.prefix(12)) { movie in
                        movieCard(movie)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(movies.prefix(15)) { movie in
                            movieCard(movie)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    private func tvShowSection(_ shows: [TrendingTVShow]) -> some View {
        Group {
            #if os(tvOS)
            LazyVGrid(columns: tvOSGridColumns, spacing: TVSizing.gridSpacing) {
                ForEach(shows.prefix(18)) { show in
                    tvShowCard(show)
                }
            }
            .padding(.horizontal, horizontalPadding)
            #else
            if isIPad {
                LazyVGrid(columns: iPadGridColumns, spacing: AppSpacing.md) {
                    ForEach(shows.prefix(12)) { show in
                        tvShowCard(show)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(shows.prefix(15)) { show in
                            tvShowCard(show)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }
            #endif
        }
    }

    // MARK: - Card Builders

    private func movieCard(_ movie: TrendingMovie) -> some View {
        let inLibrary = libraryState.isMovieInLibrary(tmdbId: movie.id)
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
                selectedMovie = movie
            }
        }
    }

    private func tvShowCard(_ show: TrendingTVShow) -> some View {
        let inLibrary = libraryState.isShowInLibrary(tvdbId: show.tvdbId, name: show.name, year: show.year)
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
                selectedTVShow = show
            }
        }
    }

    // MARK: - tvOS Navigation Bar

    #if os(tvOS)
    private var tvOSNavigationBar: some View {
        HStack {
            Text("Discover")
                .font(AppTypography.title2(.bold))
                .foregroundColor(ColorPalette.textPrimaryDark)
            Spacer()
        }
        .padding(.horizontal, TVSizing.contentPadding)
        .padding(.vertical, AppSpacing.md)
        .background(ColorPalette.backgroundDark)
    }
    #endif

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false) async {
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            // Movie fetches
            group.addTask { await loadMovieData(forceRefresh: forceRefresh) }
            // TV show fetches
            group.addTask { await loadTVShowData(forceRefresh: forceRefresh) }
            // Library state
            group.addTask { await libraryState.loadAll(forceRefresh: forceRefresh) }
        }

        if isInitialLoad {
            isInitialLoad = false
        }
    }

    private func loadMovieData(forceRefresh: Bool) async {
        do {
            async let popular = TMDBService.shared.fetchPopularMovies(forceRefresh: forceRefresh)
            async let topRated = TMDBService.shared.fetchTopRatedMovies(forceRefresh: forceRefresh)
            async let nowPlaying = TMDBService.shared.fetchNowPlayingMovies(forceRefresh: forceRefresh)
            async let upcoming = TMDBService.shared.fetchUpcomingMovies(forceRefresh: forceRefresh)

            let (fetchedPopular, fetchedTopRated, fetchedNowPlaying, fetchedUpcoming) = try await (popular, topRated, nowPlaying, upcoming)

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    popularMovies = fetchedPopular
                    topRatedMovies = fetchedTopRated
                    nowPlayingMovies = fetchedNowPlaying
                    upcomingMovies = fetchedUpcoming
                }
            }
        } catch {
            await MainActor.run {
                if !hasDataToDisplay {
                    errorMessage = "Failed to load movies from TMDB: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadTVShowData(forceRefresh: Bool) async {
        do {
            async let popular = TMDBService.shared.fetchPopularTVShows(forceRefresh: forceRefresh)
            async let topRated = TMDBService.shared.fetchTopRatedTVShows(forceRefresh: forceRefresh)
            async let onTheAir = TMDBService.shared.fetchOnTheAirTVShows(forceRefresh: forceRefresh)
            async let airingToday = TMDBService.shared.fetchAiringTodayTVShows(forceRefresh: forceRefresh)

            let (fetchedPopular, fetchedTopRated, fetchedOnTheAir, fetchedAiringToday) = try await (popular, topRated, onTheAir, airingToday)

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    popularTVShows = fetchedPopular
                    topRatedTVShows = fetchedTopRated
                    onTheAirTVShows = fetchedOnTheAir
                    airingTodayTVShows = fetchedAiringToday
                }
            }
        } catch {
            await MainActor.run {
                if !hasDataToDisplay {
                    errorMessage = "Failed to load TV shows from TMDB: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    DiscoverView()
        .preferredColorScheme(.dark)
}
