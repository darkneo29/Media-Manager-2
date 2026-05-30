import SwiftUI

struct MovieDetailView: View {
    @State private var movie: Movie
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @ObservedObject private var releaseRadar = ReleaseRadarService.shared
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var isDeleting = false

    // File management state
    @State private var movieFiles: [MovieFile] = []
    @State private var isLoadingFiles = true
    @State private var isDeletingFile = false
    @State private var isSearching = false
    @State private var showingReleaseSearch = false
    @State private var showingDeleteFileAlert = false
    @State private var fileToDelete: MovieFile?

    // Trailer state
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false

    // Toast state
    @State private var showSearchToast = false

    /// Check if we're on tvOS
    private var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    init(movie: Movie) {
        _movie = State(initialValue: movie)
    }

    private var posterURL: URL? {
        movie.images.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return RadarrService.shared.imageURL(for: image.url)
            }
    }

    private var fanartURL: URL? {
        movie.images.first(where: { $0.coverType == "fanart" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return RadarrService.shared.imageURL(for: image.url)
            }
    }

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero section with poster
                    #if os(tvOS)
                    // tvOS: Horizontal layout with larger poster
                    HStack(alignment: .top, spacing: TVSizing.gridSpacing) {
                        // Poster
                        CachedAsyncImage(url: posterURL, width: TVSizing.largePosterWidth, height: TVSizing.largePosterHeight)
                            .cornerRadius(AppRadius.xl)
                            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.xl)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                ColorPalette.primary.opacity(0.5),
                                                ColorPalette.secondary.opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )

                        // Movie info
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            Text(movie.title)
                                .font(AppTypography.largeTitle())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: AppSpacing.md) {
                                MetaPill(text: String(movie.year), icon: "calendar")

                                if movie.runtime > 0 {
                                    MetaPill(text: "\(movie.runtime) min", icon: "clock")
                                }

                                MetaPill(
                                    text: movie.status.capitalized,
                                    icon: movie.status == "released" ? "checkmark.circle.fill" : "clock.badge.questionmark"
                                )
                            }

                            // Monitored status
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: movie.monitored ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(movie.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                Text(movie.monitored ? "Monitored" : "Not Monitored")
                                    .font(AppTypography.body(.medium))
                                    .foregroundColor(movie.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                            }

                            // Watch Trailer button
                            if let trailerURL = trailerURL {
                                Button {
                                    openURL(trailerURL)
                                } label: {
                                    HStack(spacing: AppSpacing.sm) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 24))
                                        Text("Watch Trailer")
                                            .font(AppTypography.headline())
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.md)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.red, Color.red.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(AppRadius.pill)
                                }
                            }

                            // Overview
                            Text(movie.overview ?? "No overview available.")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .lineSpacing(6)
                                .lineLimit(6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()
                    }
                    .padding(.horizontal, TVSizing.contentPadding)
                    .padding(.top, TVSizing.contentPadding)
                    #else
                    ZStack(alignment: .bottom) {
                        // Background gradient
                        LinearGradient(
                            colors: [
                                ColorPalette.primary.opacity(0.3),
                                ColorPalette.backgroundDark
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 320)

                        VStack(spacing: AppSpacing.md) {
                            // Poster
                            CachedAsyncImage(url: posterURL, width: 160, height: 240)
                                .cornerRadius(AppRadius.md)
                                .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    ColorPalette.primary.opacity(0.5),
                                                    ColorPalette.secondary.opacity(0.3)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                        }
                        .padding(.bottom, AppSpacing.lg)
                    }
                    #endif

                    // Content
                    VStack(alignment: .leading, spacing: isTVOS ? AppSpacing.xl : AppSpacing.lg) {
                        #if !os(tvOS)
                        // Title and meta (iOS only - tvOS shows in hero section)
                        VStack(alignment: .center, spacing: AppSpacing.sm) {
                            Text(movie.title)
                                .font(AppTypography.title2())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.center)

                            HStack(spacing: AppSpacing.sm) {
                                MetaPill(text: String(movie.year), icon: "calendar")

                                if movie.runtime > 0 {
                                    MetaPill(text: "\(movie.runtime) min", icon: "clock")
                                }

                                MetaPill(
                                    text: movie.status.capitalized,
                                    icon: movie.status == "released" ? "checkmark.circle.fill" : "clock.badge.questionmark"
                                )
                            }

                            // Monitored status
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: movie.monitored ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(movie.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                Text(movie.monitored ? "Monitored" : "Not Monitored")
                                    .font(AppTypography.caption1(.medium))
                                    .foregroundColor(movie.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                            }
                            .padding(.top, AppSpacing.xs)

                            // Watch Trailer button
                            if isLoadingTrailer {
                                HStack(spacing: AppSpacing.xs) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading trailer...")
                                        .font(AppTypography.caption1())
                                        .foregroundColor(ColorPalette.textMutedDark)
                                }
                                .padding(.top, AppSpacing.sm)
                            } else if let trailerURL = trailerURL {
                                Button {
                                    openURL(trailerURL)
                                } label: {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Watch Trailer")
                                            .font(AppTypography.subheadline(.semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.red, Color.red.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(AppRadius.pill)
                                    .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                                .padding(.top, AppSpacing.sm)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Overview section
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            SectionTitle(text: "Overview")

                            Text(movie.overview ?? "No overview available.")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        #endif

                        // Files section
                        VStack(alignment: .leading, spacing: isTVOS ? AppSpacing.md : AppSpacing.sm) {
                            SectionTitle(text: "Files")

                            if isLoadingFiles {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(isTVOS ? 1.0 : 0.8)
                                    Text("Loading files...")
                                        .font(isTVOS ? AppTypography.body() : AppTypography.caption1())
                                        .foregroundColor(ColorPalette.textMutedDark)
                                    Spacer()
                                }
                                .padding(.vertical, AppSpacing.md)
                            } else if movieFiles.isEmpty {
                                NoFileCard(
                                    message: "No file downloaded yet. The movie is being monitored and will download when available.",
                                    onSearch: { searchForMovie() },
                                    isSearching: isSearching
                                )
                            } else {
                                ForEach(movieFiles) { file in
                                    MovieFileCard(
                                        file: file,
                                        onDelete: {
                                            fileToDelete = file
                                            showingDeleteFileAlert = true
                                        },
                                        isDeleting: isDeletingFile && fileToDelete?.id == file.id
                                    )
                                }

                                HStack(spacing: AppSpacing.sm) {
                                    Button(action: { searchForMovie() }) {
                                        HStack {
                                            if isSearching {
                                                ProgressView()
                                                    .scaleEffect(isTVOS ? 1.0 : 0.8)
                                            } else {
                                                Image(systemName: "magnifyingglass")
                                            }
                                            Text(isSearching ? "Searching..." : "Auto Search")
                                        }
                                        .font(isTVOS ? AppTypography.body(.medium) : AppTypography.subheadline(.medium))
                                        .foregroundColor(ColorPalette.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, isTVOS ? AppSpacing.md : AppSpacing.sm)
                                        .background(ColorPalette.primary.opacity(0.1))
                                        .cornerRadius(AppRadius.md)
                                    }
                                    .disabled(isSearching)

                                    Button(action: { showingReleaseSearch = true }) {
                                        HStack {
                                            Image(systemName: "list.bullet.rectangle")
                                            Text("Manual")
                                        }
                                        .font(isTVOS ? AppTypography.body(.medium) : AppTypography.subheadline(.medium))
                                        .foregroundColor(ColorPalette.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, isTVOS ? AppSpacing.md : AppSpacing.sm)
                                        .background(ColorPalette.secondary.opacity(0.1))
                                        .cornerRadius(AppRadius.md)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, isTVOS ? TVSizing.contentPadding : AppSpacing.md)

                        // Action buttons
                        VStack(spacing: isTVOS ? AppSpacing.md : AppSpacing.sm) {
                            Button {
                                releaseRadar.toggleFollow(movie: movie)
                                syncWidgetReleaseRadar()
                            } label: {
                                HStack {
                                    Image(systemName: releaseRadar.isFollowing(movie: movie) ? "star.fill" : "star")
                                    Text(releaseRadar.isFollowing(movie: movie) ? "Following in Release Radar" : "Follow in Release Radar")
                                }
                                .font(isTVOS ? AppTypography.title3() : AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: isTVOS ? 400 : .infinity)
                                .padding(.vertical, isTVOS ? AppSpacing.lg : AppSpacing.md)
                                .background(ColorPalette.secondary)
                                .cornerRadius(isTVOS ? AppRadius.lg : AppRadius.md)
                            }

                            Button {
                                showingEditSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit Movie")
                                }
                                .font(isTVOS ? AppTypography.title3() : AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: isTVOS ? 400 : .infinity)
                                .padding(.vertical, isTVOS ? AppSpacing.lg : AppSpacing.md)
                                .background(ColorPalette.primary)
                                .cornerRadius(isTVOS ? AppRadius.lg : AppRadius.md)
                            }

                            Button {
                                showingDeleteAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Movie")
                                }
                                .font(isTVOS ? AppTypography.title3() : AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: isTVOS ? 400 : .infinity)
                                .padding(.vertical, isTVOS ? AppSpacing.lg : AppSpacing.md)
                                .background(ColorPalette.error)
                                .cornerRadius(isTVOS ? AppRadius.lg : AppRadius.md)
                            }
                            .disabled(isDeleting)
                            .opacity(isDeleting ? 0.6 : 1)
                        }
                        .padding(.horizontal, isTVOS ? TVSizing.contentPadding : AppSpacing.md)
                        .padding(.top, isTVOS ? AppSpacing.lg : AppSpacing.md)
                    }
                    .padding(.bottom, isTVOS ? TVSizing.contentPadding : AppSpacing.xxl)
                }
            }
        }
        .navigationTitle("Details")
        .navBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(movie.title)?", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
            Button("Remove from Radarr Only", role: .destructive) {
                deleteMovie(deleteFiles: false, addImportExclusion: false)
            }
            Button("Remove and Delete Files", role: .destructive) {
                deleteMovie(deleteFiles: true, addImportExclusion: false)
            }
            Button("Remove, Delete Files, and Exclude", role: .destructive) {
                deleteMovie(deleteFiles: true, addImportExclusion: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether to keep files on disk or delete them.")
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            refreshMovie()
        }) {
            EditMovieView(movie: movie)
        }
        .alert("Delete File?", isPresented: $showingDeleteFileAlert) {
            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let file = fileToDelete {
                    deleteMovieFile(file)
                }
            }
        } message: {
            Text("Are you sure you want to delete this file? The movie will remain in your library but the file will be removed from disk.")
        }
        .sheet(isPresented: $showingReleaseSearch) {
            ReleaseSearchSheet(
                title: movie.title,
                loadReleases: { try await RadarrService.shared.fetchMovieReleases(movieId: movie.id) },
                grabRelease: { try await RadarrService.shared.grabRelease($0) }
            )
        }
        .task {
            loadMovieFiles()
            loadTrailer()
        }
        .toast(
            isShowing: $showSearchToast,
            message: "Search started! Radarr is looking for your movie.",
            style: .success
        )
    }

    // MARK: - Trailer Loading

    private func loadTrailer() {
        guard let tmdbId = movie.tmdbId else { return }
        isLoadingTrailer = true
        Task {
            let url = await TMDBService.shared.getMovieTrailerURL(tmdbId: tmdbId)
            await MainActor.run {
                trailerURL = url
                isLoadingTrailer = false
            }
        }
    }

    // MARK: - File Management

    private func loadMovieFiles() {
        isLoadingFiles = true
        Task {
            do {
                let files = try await RadarrService.shared.fetchMovieFiles(movieId: movie.id)
                await MainActor.run {
                    movieFiles = files
                    isLoadingFiles = false
                }
            } catch {
                #if DEBUG
                print("Error loading movie files: \(error)")
                #endif
                await MainActor.run {
                    isLoadingFiles = false
                }
            }
        }
    }

    private func deleteMovieFile(_ file: MovieFile) {
        isDeletingFile = true
        Task {
            do {
                try await RadarrService.shared.deleteMovieFile(id: file.id, movieId: movie.id)
                await MainActor.run {
                    movieFiles.removeAll { $0.id == file.id }
                    isDeletingFile = false
                    fileToDelete = nil
                }
            } catch {
                #if DEBUG
                print("Error deleting movie file: \(error)")
                #endif
                await MainActor.run {
                    isDeletingFile = false
                    fileToDelete = nil
                }
            }
        }
    }

    private func searchForMovie() {
        isSearching = true
        Task {
            do {
                try await RadarrService.shared.searchForMovie(movieId: movie.id)
                await MainActor.run {
                    isSearching = false
                    withAnimation {
                        showSearchToast = true
                    }
                }
            } catch {
                #if DEBUG
                print("Error searching for movie: \(error)")
                #endif
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }

    private func deleteMovie(deleteFiles: Bool, addImportExclusion: Bool) {
        isDeleting = true
        Task {
            do {
                try await RadarrService.shared.deleteMovie(
                    id: movie.id,
                    deleteFiles: deleteFiles,
                    addImportExclusion: addImportExclusion
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("Error deleting movie: \(error)")
                #endif
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }

    private func refreshMovie() {
        Task {
            do {
                let movies = try await RadarrService.shared.fetchMovies(forceRefresh: true)
                if let updatedMovie = movies.first(where: { $0.id == movie.id }) {
                    await MainActor.run {
                        movie = updatedMovie
                    }
                }
            } catch {
                #if DEBUG
                print("Error refreshing movie: \(error)")
                #endif
            }
        }
    }

    private func syncWidgetReleaseRadar() {
        let hasServers = ConfigurationManager.shared.isRadarrConfigured || ConfigurationManager.shared.isSonarrConfigured
        WidgetDataService.shared.updateWidgetData(
            movies: LibraryStateManager.shared.movies,
            tvShows: LibraryStateManager.shared.tvShows,
            isConfigured: hasServers,
            forceReload: true
        )
    }
}

struct MetaPill: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppTypography.caption1(.medium))
        }
        .foregroundColor(ColorPalette.textSecondaryDark)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.pill)
    }
}

struct ReleaseSearchSheet: View {
    let title: String
    let loadReleases: () async throws -> [ReleaseSearchResult]
    let grabRelease: (ReleaseSearchResult) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var releases: [ReleaseSearchResult] = []
    @State private var isLoading = true
    @State private var grabbingReleaseId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(ColorPalette.primary)
                } else if let errorMessage {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(ColorPalette.error)
                        Text(errorMessage)
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                    }
                    .padding(AppSpacing.lg)
                } else if releases.isEmpty {
                    PlaceholderView(
                        icon: "magnifyingglass",
                        title: "No Releases Found",
                        description: "No matching releases were returned."
                    )
                } else {
                    List {
                        ForEach(releases) { release in
                            ReleaseResultRow(
                                release: release,
                                isGrabbing: grabbingReleaseId == release.id,
                                onGrab: { grab(release) }
                            )
                            .listRowBackground(ColorPalette.backgroundDark)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Manual Search")
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
        .presentationDetents([.large])
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let results = try await loadReleases()
            await MainActor.run {
                releases = results.sorted { lhs, rhs in
                    if lhs.approved == rhs.approved {
                        return (lhs.size ?? 0) < (rhs.size ?? 0)
                    }
                    return lhs.approved == true
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func grab(_ release: ReleaseSearchResult) {
        grabbingReleaseId = release.id
        Task {
            do {
                try await grabRelease(release)
                await MainActor.run {
                    grabbingReleaseId = nil
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    grabbingReleaseId = nil
                }
            }
        }
    }
}

private struct ReleaseResultRow: View {
    let release: ReleaseSearchResult
    let isGrabbing: Bool
    let onGrab: () -> Void

    private var isRejected: Bool {
        release.rejected == true || !(release.rejections?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(release.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(3)

                    HStack(spacing: AppSpacing.xs) {
                        QualityPill(text: release.qualityName)
                        CodecPill(text: release.formattedSize)
                        if !release.ageDisplay.isEmpty {
                            CodecPill(text: release.ageDisplay)
                        }
                        if let seeders = release.seeders {
                            CodecPill(text: "\(seeders) seeds")
                        }
                    }
                }

                Spacer()

                Button(action: onGrab) {
                    if isGrabbing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                    }
                }
                .foregroundColor(isRejected ? ColorPalette.textMutedDark : ColorPalette.primary)
                .disabled(isGrabbing || isRejected)
            }

            if let indexer = release.indexer, !indexer.isEmpty {
                Text(indexer)
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.secondary)
            }

            if isRejected {
                Text(release.rejectionSummary)
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [ColorPalette.primary, ColorPalette.secondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 3, height: 20)
                .cornerRadius(2)

            Text(text)
                .font(AppTypography.headline())
                .foregroundColor(ColorPalette.textPrimaryDark)
        }
    }
}
