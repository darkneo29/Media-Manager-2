import SwiftUI

struct MovieListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var configuration = ConfigurationManager.shared

    @ObservedObject private var libraryManager = LibraryStateManager.shared
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var isSelectionMode = false
    @State private var selectedMovieIds: Set<Int> = []
    @State private var isRunningBulkAction = false
    @State private var showingBulkDelete = false
    @State private var qualityProfiles: [RadarrQualityProfile] = []

    // MARK: - Cached/Memoized State for tvOS Performance
    @State private var cachedFilteredMovies: [Movie] = []
    @State private var lastSearchText: String = ""
    @State private var lastMoviesRevision: Int = -1

    /// Deep link movie ID binding - set by MainTabView for widget navigation
    @Binding var deepLinkMovieId: Int?

    init(deepLinkMovieId: Binding<Int?> = .constant(nil)) {
        self._deepLinkMovieId = deepLinkMovieId
    }

    private var isConfigured: Bool {
        configuration.isRadarrConfigured
    }

    /// Memoized filtered movies - returns cached result (updated via updateFilteredMovies)
    var filteredMovies: [Movie] {
        return cachedFilteredMovies
    }

    /// Update cached filtered movies when inputs change
    private func updateFilteredMovies() {
        let movies = libraryManager.sortedMovies
        let currentRevision = libraryManager.moviesRevision

        // Only recompute if something changed
        guard searchText != lastSearchText || currentRevision != lastMoviesRevision else { return }

        lastSearchText = searchText
        lastMoviesRevision = currentRevision

        if searchText.isEmpty {
            cachedFilteredMovies = movies
        } else {
            cachedFilteredMovies = movies.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        // Prefetch images for visible items on tvOS
        #if os(tvOS)
        prefetchVisibleImages()
        #endif
    }

    /// Prefetch images for better scroll performance on tvOS
    private func prefetchVisibleImages() {
        let visibleCount = TVSizing.gridColumns * 3  // Prefetch 3 rows worth
        let urls = cachedFilteredMovies.prefix(visibleCount).compactMap { movie -> URL? in
            movie.images.first(where: { $0.coverType == "poster" })
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
                        title: "Radarr Not Configured",
                        description: "Go to Settings to configure your Radarr server URL and API key",
                        action: TVSizing.isTV ? .openSettings : nil
                    )
                } else if libraryManager.isLoadingMovies && libraryManager.movies.isEmpty {
                    ProgressView()
                        .tint(ColorPalette.primary)
                } else if let message = libraryManager.moviesErrorMessage, libraryManager.movies.isEmpty {
                    PlaceholderView(
                        icon: "wifi.exclamationmark",
                        title: "Couldn't Load Movies",
                        description: message,
                        action: PlaceholderView.ActionConfig(
                            title: "Try Again",
                            icon: "arrow.clockwise",
                            handler: {
                                Task {
                                    await libraryManager.loadMovies(forceRefresh: true)
                                    updateFilteredMovies()
                                    handlePendingDeepLink()
                                }
                            }
                        )
                    )
                } else if filteredMovies.isEmpty && !searchText.isEmpty {
                    VStack(spacing: isTVOS ? AppSpacing.lg : AppSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: isTVOS ? 80 : 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No movies found")
                            .font(isTVOS ? AppTypography.title2() : AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text("Try a different search term")
                            .font(isTVOS ? AppTypography.body() : AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                } else if libraryManager.movies.isEmpty {
                    VStack(spacing: isTVOS ? AppSpacing.lg : AppSpacing.md) {
                        Image(systemName: "film")
                            .font(.system(size: isTVOS ? 80 : 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No movies in library")
                            .font(isTVOS ? AppTypography.title2() : AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text("Choose Add to search for movies")
                            .font(isTVOS ? AppTypography.body() : AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: isTVOS ? TVSizing.gridSpacing : AppSpacing.sm) {
                            ForEach(filteredMovies) { movie in
                                #if os(tvOS)
                                TVMoviePosterCard(movie: movie) {
                                    handleMovieTap(movie)
                                }
                                .overlay(alignment: .topTrailing) {
                                    selectionBadge(for: movie)
                                }
                                #else
                                BookshelfMovieCard(movie: movie) {
                                    handleMovieTap(movie)
                                }
                                .overlay(alignment: .topTrailing) {
                                    selectionBadge(for: movie)
                                }
                                #endif
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, isTVOS ? TVSizing.contentPadding : AppSpacing.sm)
                        .padding(.bottom, isTVOS ? TVSizing.contentPadding : AppSpacing.xl)
                    }
                    .refreshable {
                        await libraryManager.loadMovies(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("Movies")
            .navBarTitleDisplayMode(.large)
            #if os(tvOS)
            .safeAreaInset(edge: .top) {
                tvLibraryActions
            }
            #else
            .searchable(text: $searchText, prompt: "Search movies...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.sm) {
                        if !libraryManager.movies.isEmpty {
                            Button(isSelectionMode ? "Done" : "Select") {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedMovieIds.removeAll()
                                }
                            }
                            .foregroundColor(ColorPalette.secondary)
                        }

                        NavigationLink(destination: RadarrCollectionsView()) {
                            Image(systemName: "rectangle.stack")
                                .foregroundColor(ColorPalette.secondary)
                        }
                        .accessibilityLabel("Radarr Collections")

                        NavigationLink(destination: AddMovieView(navigationPath: $navigationPath)) {
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
                            await libraryManager.loadMovies(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(ColorPalette.secondary)
                    }
                    .disabled(libraryManager.isLoadingMovies)
                }
            }
            #endif
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
            .task {
                if isConfigured && libraryManager.movies.isEmpty {
                    await libraryManager.loadMovies()
                }
                if isConfigured && qualityProfiles.isEmpty {
                    loadQualityProfiles()
                }
                updateFilteredMovies()
                handlePendingDeepLink()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredMovies()
            }
            .onChange(of: deepLinkMovieId) { _, movieId in
                // Handle deep link navigation from widget
                handlePendingDeepLink(movieId)
                // Don't clear deepLinkMovieId if movie not found - retry when data loads
            }
            .onChange(of: libraryManager.moviesRevision) { _, _ in
                updateFilteredMovies()
                // Retry deep link if pending
                handlePendingDeepLink()
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
                if isSelectionMode && !selectedMovieIds.isEmpty {
                    bulkActionBar
                }
            }
            .confirmationDialog("Delete selected movies?", isPresented: $showingBulkDelete, titleVisibility: .visible) {
                Button("Remove from Radarr Only", role: .destructive) {
                    runBulkDelete(deleteFiles: false)
                }
                Button("Remove and Delete Files", role: .destructive) {
                    runBulkDelete(deleteFiles: true)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }


    #if os(tvOS)
    private var tvLibraryActions: some View {
        HStack(spacing: 24) {
            TVLibrarySearchButton(text: $searchText, title: "Search Movies")
            Spacer(minLength: 24)
            NavigationLink(destination: RadarrCollectionsView()) {
                Label("Collections", systemImage: "rectangle.stack")
            }

            if !libraryManager.movies.isEmpty {
                Button(isSelectionMode ? "Done" : "Select") {
                    isSelectionMode.toggle()
                    if !isSelectionMode { selectedMovieIds.removeAll() }
                }
            }
            NavigationLink(destination: AddMovieView(navigationPath: $navigationPath)) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(TVInterfaceButtonStyle(prominent: true))
            .disabled(!isConfigured)
            Button {
                Task { await libraryManager.loadMovies(forceRefresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh library")
            .disabled(!isConfigured || libraryManager.isLoadingMovies)
        }
        .buttonStyle(TVInterfaceButtonStyle())
        .padding(.horizontal, TVSizing.contentPadding)
        .padding(.vertical, 24)
        .background(ColorPalette.backgroundDark)
    }
    #endif

    @ViewBuilder
    private func selectionBadge(for movie: Movie) -> some View {
        if isSelectionMode {
            Image(systemName: selectedMovieIds.contains(movie.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(selectedMovieIds.contains(movie.id) ? ColorPalette.primary : ColorPalette.textSecondaryDark)
                .padding(AppSpacing.sm)
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(selectedMovieIds.count) selected")
                .font(AppTypography.caption1(.semibold))
                .foregroundColor(ColorPalette.textSecondaryDark)

            Spacer()

            Button { runBulkMonitoring(monitored: true) } label: {
                Label("Monitor", systemImage: "eye.fill")
            }
            Button { runBulkMonitoring(monitored: false) } label: {
                Label("Unmonitor", systemImage: "eye.slash.fill")
            }
            Button { runBulkSearch() } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            Menu {
                ForEach(qualityProfiles) { profile in
                    Button(profile.name) {
                        runBulkQualityChange(profileId: profile.id)
                    }
                }
            } label: {
                Label("Quality", systemImage: "slider.horizontal.3")
            }
            .disabled(qualityProfiles.isEmpty)
            Button(role: .destructive) { showingBulkDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #if os(tvOS)
        .buttonStyle(TVInterfaceButtonStyle())
        #else
        .labelStyle(.iconOnly)
        #endif
        .font(AppTypography.body(.semibold))
        .foregroundColor(ColorPalette.primary)
        .padding(AppSpacing.md)
        .background(.ultraThinMaterial)
        .disabled(isRunningBulkAction)
    }

    private func handleMovieTap(_ movie: Movie) {
        if isSelectionMode {
            if selectedMovieIds.contains(movie.id) {
                selectedMovieIds.remove(movie.id)
            } else {
                selectedMovieIds.insert(movie.id)
            }
        } else {
            navigationPath.append(movie)
        }
    }

    private func handlePendingDeepLink(_ movieId: Int? = nil) {
        guard let movieId = movieId ?? deepLinkMovieId,
              let movie = LibraryDeepLink.resolve(movieId, in: libraryManager.movies) else {
            return
        }

        navigationPath.append(movie)
        deepLinkMovieId = nil
    }

    private func selectedMovies() -> [Movie] {
        libraryManager.movies.filter { selectedMovieIds.contains($0.id) }
    }

    private func loadQualityProfiles() {
        Task {
            do {
                let profiles = try await RadarrService.shared.fetchQualityProfiles()
                await MainActor.run {
                    qualityProfiles = profiles
                }
            } catch {
                #if DEBUG
                print("Error loading Radarr quality profiles: \(error)")
                #endif
            }
        }
    }

    private func runBulkMonitoring(monitored: Bool) {
        isRunningBulkAction = true
        Task {
            do {
                try await RadarrService.shared.editMovies(ids: Array(selectedMovieIds), monitored: monitored)
                await libraryManager.loadMovies(forceRefresh: true)
                await MainActor.run {
                    selectedMovieIds.removeAll()
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
                try await RadarrService.shared.searchForMovies(ids: Array(selectedMovieIds))
                await MainActor.run {
                    selectedMovieIds.removeAll()
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
                try await RadarrService.shared.editMovies(ids: Array(selectedMovieIds), qualityProfileId: profileId)
                await libraryManager.loadMovies(forceRefresh: true)
                await MainActor.run {
                    selectedMovieIds.removeAll()
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
                try await RadarrService.shared.deleteMovies(ids: Array(selectedMovieIds), deleteFiles: deleteFiles)
                await libraryManager.loadMovies(forceRefresh: true)
                await MainActor.run {
                    selectedMovieIds.removeAll()
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
