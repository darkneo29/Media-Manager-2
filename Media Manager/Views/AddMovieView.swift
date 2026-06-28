import SwiftUI
import Combine

struct AddMovieView: View {
    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @State private var searchResults: [MovieLookup] = []
    @State private var tmdbResults: [TrendingMovie] = []
    @State private var selectedTMDBMovie: TrendingMovie?
    @State private var isSearching = false
    @State private var addingMovieId: Int?
    @State private var errorMessage: String?

    // Quality profile and root folder state
    @State private var qualityProfiles: [RadarrQualityProfile] = []
    @State private var rootFolders: [RootFolder] = []
    @State private var selectedQualityProfileId: Int = 1
    @State private var selectedRootFolderPath: String = ""
    @State private var isLoadingOptions = true
    @State private var optionsErrorMessage: String?
    @State private var searchForMovie: Bool = true

    // Debouncing support
    @State private var searchTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 300_000_000 // 300ms in nanoseconds
    @FocusState private var isSearchFieldFocused: Bool

    @Environment(\.dismiss) var dismiss

    private var canAddMovie: Bool {
        !isLoadingOptions && optionsErrorMessage == nil && !qualityProfiles.isEmpty && !rootFolders.isEmpty
    }

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ColorPalette.textMutedDark)
                        TextField("Search for movie...", text: $searchText)
                            .foregroundColor(ColorPalette.textPrimaryDark)
                            .focused($isSearchFieldFocused)
                            .submitLabel(.search)
                            .onChange(of: searchText) { _, newValue in
                                debouncedSearch(newValue)
                            }
                            .onSubmit {
                                submitSearch()
                            }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                                tmdbResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ColorPalette.textMutedDark)
                            }
                        }
                    }
                    .padding(AppSpacing.sm)
                    .background(ColorPalette.cardBackgroundDark)
                    .cornerRadius(AppRadius.md)

                    Button {
                        submitSearch()
                    } label: {
                        Text("Search")
                            .font(AppTypography.subheadline(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(ColorPalette.primary)
                            .cornerRadius(AppRadius.md)
                    }
                    .disabled(searchText.isEmpty || isSearching)
                    .opacity(searchText.isEmpty ? 0.5 : 1)
                }
                .padding(AppSpacing.md)

                // Add options section
                #if os(tvOS)
                tvOSOptionsSection
                #else
                iOSOptionsSection
                #endif

                if let optionsErrorMessage {
                    optionErrorBanner(message: optionsErrorMessage) {
                        loadOptions(forceRefresh: true)
                    }
                }

                Divider()
                    .background(ColorPalette.divider)

                // Content
                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(ColorPalette.primary)
                    Text("Searching...")
                        .font(AppTypography.caption1())
                        .foregroundColor(ColorPalette.textMutedDark)
                        .padding(.top, AppSpacing.sm)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.error)
                        Text(error)
                            .font(AppTypography.subheadline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else if searchResults.isEmpty && tmdbResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "film")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No results found")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text("Try a different search term")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                    Spacer()
                } else if searchResults.isEmpty && tmdbResults.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("Search for movies")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        Text("Find movies to add to your library")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            // Radarr results
                            ForEach(searchResults) { movie in
                                SearchResultCard(movie: movie, isAdding: addingMovieId == movie.tmdbId) {
                                    addMovie(movie)
                                }
                            }

                            // TMDB-only results
                            if !tmdbResults.isEmpty {
                                HStack {
                                    Text("More Results")
                                        .font(AppTypography.subheadline(.semibold))
                                        .foregroundColor(ColorPalette.textSecondaryDark)
                                    Spacer()
                                }
                                .padding(.top, AppSpacing.sm)

                                ForEach(tmdbResults) { movie in
                                    TMDBSearchResultCard(movie: movie) {
                                        selectedTMDBMovie = movie
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.xl)
                    }
                }
            }
        }
        .navigationTitle("Add Movie")
        .navBarTitleDisplayMode(.inline)
        .onAppear {
            loadOptions()
        }
        .onDisappear {
            if let movie = pendingMovie {
                pendingMovie = nil
                navigationPath.append(movie)
            }
        }
        .sheet(item: $selectedTMDBMovie) { movie in
            QuickAddMovieSheet(movie: movie) {
                // Movie was added — refresh isn't needed since we'll dismiss
            }
        }
    }

    // MARK: - iOS Options Section

    #if !os(tvOS)
    private var iOSOptionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Quality profile picker
            HStack {
                Text("Quality Profile")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                if isLoadingOptions {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(ColorPalette.secondary)
                } else {
                    Picker("Quality Profile", selection: $selectedQualityProfileId) {
                        ForEach(qualityProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorPalette.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Root folder picker
            HStack {
                Text("Root Folder")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                if isLoadingOptions {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(ColorPalette.secondary)
                } else {
                    Picker("Root Folder", selection: $selectedRootFolderPath) {
                        ForEach(rootFolders) { folder in
                            Text(folder.folderName).tag(folder.path)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorPalette.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Search for movie toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search for Movie")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Start searching when movie is added")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $searchForMovie)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
    }
    #endif

    // MARK: - tvOS Options Section

    #if os(tvOS)
    private var tvOSOptionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Quality profile picker
            TVAddMoviePickerRow(
                title: "Quality Profile",
                isLoading: isLoadingOptions,
                selectedLabel: qualityProfiles.first { $0.id == selectedQualityProfileId }?.name ?? "Select..."
            ) {
                // Cycle through quality profiles
                if let currentIndex = qualityProfiles.firstIndex(where: { $0.id == selectedQualityProfileId }) {
                    let nextIndex = (currentIndex + 1) % qualityProfiles.count
                    selectedQualityProfileId = qualityProfiles[nextIndex].id
                } else if let first = qualityProfiles.first {
                    selectedQualityProfileId = first.id
                }
            }

            // Root folder picker
            TVAddMoviePickerRow(
                title: "Root Folder",
                isLoading: isLoadingOptions,
                selectedLabel: rootFolders.first { $0.path == selectedRootFolderPath }?.folderName ?? "Select..."
            ) {
                // Cycle through root folders
                if let currentIndex = rootFolders.firstIndex(where: { $0.path == selectedRootFolderPath }) {
                    let nextIndex = (currentIndex + 1) % rootFolders.count
                    selectedRootFolderPath = rootFolders[nextIndex].path
                } else if let first = rootFolders.first {
                    selectedRootFolderPath = first.path
                }
            }

            // Search for movie toggle
            TVAddMovieToggleRow(
                title: "Search for Movie",
                subtitle: "Start searching when movie is added",
                isOn: $searchForMovie
            )
        }
        .padding(.horizontal, TVSizing.contentPadding)
        .padding(.bottom, AppSpacing.md)
    }
    #endif

    private func loadOptions(forceRefresh: Bool = false) {
        isLoadingOptions = true
        optionsErrorMessage = nil
        Task {
            do {
                async let profilesTask = RadarrService.shared.fetchQualityProfiles(forceRefresh: forceRefresh)
                async let foldersTask = RadarrService.shared.fetchRootFolders(forceRefresh: forceRefresh)

                let (profiles, folders) = try await (profilesTask, foldersTask)

                await MainActor.run {
                    qualityProfiles = profiles
                    rootFolders = folders
                    optionsErrorMessage = nil

                    // Select first profile or HD-1080p if available
                    if let hdProfile = profiles.first(where: { $0.name.contains("1080") || $0.name.contains("HD") }) {
                        selectedQualityProfileId = hdProfile.id
                    } else if let first = profiles.first {
                        selectedQualityProfileId = first.id
                    }

                    // Select first root folder
                    if let first = folders.first {
                        selectedRootFolderPath = first.path
                    }

                    isLoadingOptions = false
                }
            } catch {
                await MainActor.run {
                    optionsErrorMessage = "Could not load Radarr profiles or root folders: \(error.localizedDescription)"
                    isLoadingOptions = false
                }
            }
        }
    }

    /// Debounced search - waits for user to stop typing before searching
    private func debouncedSearch(_ query: String) {
        // Cancel any existing debounce task
        searchTask?.cancel()

        // Don't search if query is empty
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            tmdbResults = []
            return
        }

        // Create new debounced search task
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceDelay)

                // Check if task was cancelled during sleep
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    performSearch()
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        errorMessage = nil

        Task {
            do {
                async let radarrTask = RadarrService.shared.searchMovies(term: query)
                async let tmdbTask = TMDBService.shared.searchMovies(query: query)

                let radarrResults = try await radarrTask
                let tmdbSearchResults: [TrendingMovie]
                do {
                    tmdbSearchResults = try await tmdbTask
                } catch {
                    // TMDB search is supplementary — don't fail if it errors
                    tmdbSearchResults = []
                }

                // Deduplicate: exclude TMDB results that already appear in Radarr results
                let radarrTmdbIds = Set(radarrResults.map(\.tmdbId))
                let filteredTMDB = tmdbSearchResults.filter { !radarrTmdbIds.contains($0.id) }

                await MainActor.run {
                    searchResults = radarrResults
                    tmdbResults = filteredTMDB
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func submitSearch() {
        searchTask?.cancel()
        isSearchFieldFocused = false
        performSearch()
    }

    @State private var pendingMovie: Movie?

    private func addMovie(_ movie: MovieLookup) {
        guard canAddMovie else {
            errorMessage = optionsErrorMessage ?? "Load a quality profile and root folder before adding a movie."
            return
        }

        addingMovieId = movie.tmdbId
        Task {
            do {
                let addedMovie = try await RadarrService.shared.addMovie(
                    movie: movie,
                    qualityProfileId: selectedQualityProfileId,
                    rootFolderPath: selectedRootFolderPath.isEmpty ? "/movies/" : selectedRootFolderPath,
                    searchForMovie: searchForMovie
                )
                await MainActor.run {
                    LibraryStateManager.shared.addMovieLocally(addedMovie)
                    pendingMovie = addedMovie
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add movie: \(error.localizedDescription)"
                    addingMovieId = nil
                }
            }
        }
    }

    private func optionErrorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(ColorPalette.warning)

            Text(message)
                .font(AppTypography.caption1())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Retry", action: retry)
                .font(AppTypography.caption1(.semibold))
                .foregroundColor(ColorPalette.secondary)
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.warning.opacity(0.12))
        .cornerRadius(AppRadius.md)
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
    }
}

struct SearchResultCard: View {
    let movie: MovieLookup
    let isAdding: Bool
    let onAdd: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false
    @State private var trailerUnavailable = false

    /// Movie is already in library if it has a radarrId
    private var isInLibrary: Bool {
        movie.radarrId != nil
    }

    private var posterURL: URL? {
        movie.images?.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return RadarrService.shared.imageURL(for: image.url)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                // Poster
                CachedAsyncImage(url: posterURL, width: 60, height: 90)
                    .cornerRadius(AppRadius.sm)

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(movie.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.xs) {
                        Text(String(movie.year))
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(ColorPalette.secondary)

                        if movie.runtime > 0 {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text("\(movie.runtime) min")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textMutedDark)
                        }
                    }

                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppSpacing.sm) {
                SearchTrailerButton(
                    isLoading: isLoadingTrailer,
                    isUnavailable: trailerUnavailable,
                    action: watchTrailer
                )

                Spacer(minLength: AppSpacing.sm)

                // Add button or In Library badge
                if isInLibrary {
                    Text("In Library")
                        .font(AppTypography.caption1(.medium))
                        .foregroundColor(ColorPalette.success)
                        .frame(width: 86, height: 34)
                        .background(ColorPalette.success.opacity(0.15))
                        .cornerRadius(AppRadius.sm)
                } else {
                    Button(action: onAdd) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 76, height: 34)
                        } else {
                            Text("Add")
                                .font(AppTypography.caption1(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 76, height: 34)
                                .background(ColorPalette.primary)
                                .cornerRadius(AppRadius.sm)
                        }
                    }
                    .disabled(isAdding)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }

    private func watchTrailer() {
        if let trailerURL {
            openURL(trailerURL)
            return
        }

        trailerUnavailable = false
        isLoadingTrailer = true

        Task {
            let url = await TMDBService.shared.getMovieTrailerURL(tmdbId: movie.tmdbId)

            await MainActor.run {
                isLoadingTrailer = false
                guard let url else {
                    trailerUnavailable = true
                    return
                }

                trailerURL = url
                openURL(url)
            }
        }
    }
}

struct TMDBSearchResultCard: View {
    let movie: TrendingMovie
    let onAdd: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false
    @State private var trailerUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                // Poster
                CachedAsyncImage(url: movie.posterURL, width: 60, height: 90)
                    .cornerRadius(AppRadius.sm)

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(movie.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.xs) {
                        if let year = movie.year {
                            Text(String(year))
                                .font(AppTypography.caption1(.medium))
                                .foregroundColor(ColorPalette.secondary)
                        }

                        if let rating = movie.voteAverage, rating > 0 {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(ColorPalette.warning)
                                Text(String(format: "%.1f", rating))
                                    .font(AppTypography.caption1())
                                    .foregroundColor(ColorPalette.textMutedDark)
                            }
                        }
                    }

                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppSpacing.sm) {
                SearchTrailerButton(
                    isLoading: isLoadingTrailer,
                    isUnavailable: trailerUnavailable,
                    action: watchTrailer
                )

                Spacer(minLength: AppSpacing.sm)

                // Add button
                Button(action: onAdd) {
                    Text("Add")
                        .font(AppTypography.caption1(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 76, height: 34)
                        .background(ColorPalette.primary)
                        .cornerRadius(AppRadius.sm)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }

    private func watchTrailer() {
        if let trailerURL {
            openURL(trailerURL)
            return
        }

        trailerUnavailable = false
        isLoadingTrailer = true

        Task {
            let url = await TMDBService.shared.getMovieTrailerURL(tmdbId: movie.id)

            await MainActor.run {
                isLoadingTrailer = false
                guard let url else {
                    trailerUnavailable = true
                    return
                }

                trailerURL = url
                openURL(url)
            }
        }
    }
}

// MARK: - tvOS Picker Row

#if os(tvOS)
struct TVAddMoviePickerRow: View {
    let title: String
    let isLoading: Bool
    let selectedLabel: String
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(ColorPalette.secondary)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    Text(selectedLabel)
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 20))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(isFocused ? ColorPalette.cardBackgroundElevatedDark : ColorPalette.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(isFocused ? ColorPalette.secondary : ColorPalette.divider, lineWidth: isFocused ? 4 : 1)
        )
        .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
        .shadow(
            color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
            radius: isFocused ? TVSizing.focusShadowRadius : 0
        )
        .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            onTap()
        }
        .disabled(isLoading)
    }
}

struct TVAddMovieToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 22))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            Spacer()

            // Toggle indicator
            ZStack {
                Capsule()
                    .fill(isOn ? ColorPalette.secondary : Color.gray.opacity(0.3))
                    .frame(width: 70, height: 40)

                Circle()
                    .fill(Color.white)
                    .frame(width: 32, height: 32)
                    .offset(x: isOn ? 14 : -14)
                    .animation(.easeInOut(duration: 0.2), value: isOn)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(isFocused ? ColorPalette.cardBackgroundElevatedDark : ColorPalette.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(isFocused ? ColorPalette.secondary : ColorPalette.divider, lineWidth: isFocused ? 4 : 1)
        )
        .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
        .shadow(
            color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
            radius: isFocused ? TVSizing.focusShadowRadius : 0
        )
        .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            isOn.toggle()
        }
    }
}
#endif
