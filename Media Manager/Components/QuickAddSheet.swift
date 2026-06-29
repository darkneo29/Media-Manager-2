import SwiftUI

// MARK: - Quick Add Movie Sheet

struct QuickAddMovieSheet: View {
    let movie: TrendingMovie
    let onAdded: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var isSuccess = false
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false

    // Add options state
    @State private var qualityProfiles: [RadarrQualityProfile] = []
    @State private var rootFolders: [RootFolder] = []
    @State private var selectedQualityProfileId: Int = 1
    @State private var selectedRootFolderPath: String = ""
    @State private var selectedMinimumAvailability: RadarrMinimumAvailability = .released
    @State private var monitored: Bool = true
    @State private var selectedTagIds: Set<Int> = []
    @State private var tags: [MediaTag] = []
    @State private var isLoadingOptions = true
    @State private var searchForMovie: Bool = true

    private var selectedTagSummary: String {
        tagSummary(selectedTagIds: selectedTagIds, tags: tags)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(ColorPalette.textMutedDark)
                .frame(width: 36, height: 5)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Poster and info
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        // Poster
                        CachedAsyncImage(url: movie.posterURL, width: 120, height: 180)
                            .cornerRadius(AppRadius.md)

                        // Info
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(movie.title)
                                .font(AppTypography.title3())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .lineLimit(3)

                            if let year = movie.year {
                                Text("\(year)")
                                    .font(AppTypography.subheadline(.medium))
                                    .foregroundColor(ColorPalette.secondary)
                            }

                            if let rating = movie.voteAverage, rating > 0 {
                                HStack(spacing: AppSpacing.xxs) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(ColorPalette.warning)
                                        .font(.system(size: 12))
                                    Text(String(format: "%.1f", rating))
                                        .font(AppTypography.caption1(.medium))
                                        .foregroundColor(ColorPalette.textSecondaryDark)
                                }
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Overview
                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(4)
                    }

                    // Trailer button
                    if isLoadingTrailer {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.textSecondaryDark))
                                .scaleEffect(0.8)
                            Text("Loading trailer...")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                        }
                    } else if let url = trailerURL {
                        Button(action: { openURL(url) }) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "play.fill")
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
                            .cornerRadius(AppRadius.md)
                        }
                    }

                    // Add options section
                    #if os(tvOS)
                    movieOptionsSectionTV
                    #else
                    movieOptionsSectioniOS
                    #endif

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ColorPalette.error)
                            Text(error)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.error)
                        }
                        .padding()
                        .background(ColorPalette.error.opacity(0.1))
                        .cornerRadius(AppRadius.sm)
                    }

                    // Success message
                    if isSuccess {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorPalette.success)
                            Text("Movie added to Radarr!")
                                .font(AppTypography.subheadline(.medium))
                                .foregroundColor(ColorPalette.success)
                        }
                        .padding()
                        .background(ColorPalette.success.opacity(0.1))
                        .cornerRadius(AppRadius.sm)
                    }

                    Spacer(minLength: AppSpacing.lg)

                    // Add button
                    Button(action: addMovie) {
                        HStack(spacing: AppSpacing.xs) {
                            if isAdding {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else if isSuccess {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text(isSuccess ? "Added!" : "Add to Radarr")
                                .font(AppTypography.body(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSuccess ? ColorPalette.success : ColorPalette.primary)
                        .cornerRadius(AppRadius.md)
                    }
                    .disabled(isAdding || isSuccess)

                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }
        }
        .background(ColorPalette.backgroundDark)
        .task {
            loadTrailer()
            await loadOptions()
        }
    }

    // MARK: - iOS Options Section

    #if !os(tvOS)
    private var movieOptionsSectioniOS: some View {
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

            // Minimum availability picker
            HStack {
                Text("Minimum Availability")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                Picker("Minimum Availability", selection: $selectedMinimumAvailability) {
                    ForEach(RadarrMinimumAvailability.allCases) { availability in
                        Text(availability.displayName).tag(availability)
                    }
                }
                .pickerStyle(.menu)
                .tint(ColorPalette.secondary)
                .disabled(isLoadingOptions)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            if !tags.isEmpty {
                TagSelectionMenuRow(
                    title: "Tags",
                    selectedLabel: selectedTagSummary,
                    tags: tags,
                    selectedTagIds: $selectedTagIds
                )
            }

            // Monitored toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitored")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Let Radarr manage this movie after adding")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $monitored)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
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
    }
    #endif

    // MARK: - tvOS Options Section

    #if os(tvOS)
    private var movieOptionsSectionTV: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Quality profile picker
            QuickAddPickerRow(
                title: "Quality Profile",
                isLoading: isLoadingOptions,
                selectedLabel: qualityProfiles.first { $0.id == selectedQualityProfileId }?.name ?? "Select..."
            ) {
                if let currentIndex = qualityProfiles.firstIndex(where: { $0.id == selectedQualityProfileId }) {
                    let nextIndex = (currentIndex + 1) % qualityProfiles.count
                    selectedQualityProfileId = qualityProfiles[nextIndex].id
                } else if let first = qualityProfiles.first {
                    selectedQualityProfileId = first.id
                }
            }

            // Root folder picker
            QuickAddPickerRow(
                title: "Root Folder",
                isLoading: isLoadingOptions,
                selectedLabel: rootFolders.first { $0.path == selectedRootFolderPath }?.folderName ?? "Select..."
            ) {
                if let currentIndex = rootFolders.firstIndex(where: { $0.path == selectedRootFolderPath }) {
                    let nextIndex = (currentIndex + 1) % rootFolders.count
                    selectedRootFolderPath = rootFolders[nextIndex].path
                } else if let first = rootFolders.first {
                    selectedRootFolderPath = first.path
                }
            }

            QuickAddPickerRow(
                title: "Minimum Availability",
                isLoading: isLoadingOptions,
                selectedLabel: selectedMinimumAvailability.displayName
            ) {
                let allCases = RadarrMinimumAvailability.allCases
                if let currentIndex = allCases.firstIndex(of: selectedMinimumAvailability) {
                    let nextIndex = (currentIndex + 1) % allCases.count
                    selectedMinimumAvailability = allCases[nextIndex]
                }
            }

            QuickAddToggleRow(
                title: "Monitored",
                subtitle: "Let Radarr manage this movie after adding",
                isOn: $monitored
            )

            // Search for movie toggle
            QuickAddToggleRow(
                title: "Search for Movie",
                subtitle: "Start searching when movie is added",
                isOn: $searchForMovie
            )
        }
    }
    #endif

    private func loadOptions() async {
        do {
            async let profilesTask = RadarrService.shared.fetchQualityProfiles()
            async let foldersTask = RadarrService.shared.fetchRootFolders()
            async let tagsTask: [MediaTag] = (try? await RadarrService.shared.fetchTags()) ?? []

            let (profiles, folders, fetchedTags) = try await (profilesTask, foldersTask, tagsTask)

            await MainActor.run {
                qualityProfiles = profiles
                rootFolders = folders
                tags = fetchedTags

                let preferences = AddMediaPreferences.shared.radarrSettings(
                    profiles: profiles,
                    rootFolders: folders,
                    tags: fetchedTags
                )
                selectedQualityProfileId = preferences.qualityProfileId
                selectedRootFolderPath = preferences.rootFolderPath
                selectedMinimumAvailability = preferences.minimumAvailability
                monitored = preferences.monitored
                searchForMovie = preferences.searchForMovie
                selectedTagIds = Set(preferences.tagIds)

                isLoadingOptions = false
            }
        } catch {
            await MainActor.run {
                isLoadingOptions = false
            }
        }
    }

    private func loadTrailer() {
        isLoadingTrailer = true
        Task {
            let url = await TMDBService.shared.getMovieTrailerURL(tmdbId: movie.id)
            await MainActor.run {
                trailerURL = url
                isLoadingTrailer = false
            }
        }
    }

    private func addMovie() {
        guard !isLoadingOptions, !qualityProfiles.isEmpty, !rootFolders.isEmpty else {
            errorMessage = "Load a quality profile and root folder before adding this movie."
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            do {
                persistCurrentPreferences()
                // Use cached search - the CacheManager will deduplicate if same search is in progress
                let results = try await RadarrService.shared.searchMovies(term: movie.title)

                // Find the matching movie by TMDB ID
                guard let movieLookup = results.first(where: { $0.tmdbId == movie.id }) ?? results.first else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Movie not found in Radarr"])
                }

                // Add to Radarr with selected options
                let addedMovie = try await RadarrService.shared.addMovie(
                    movie: movieLookup,
                    qualityProfileId: selectedQualityProfileId,
                    rootFolderPath: selectedRootFolderPath.isEmpty ? "/movies/" : selectedRootFolderPath,
                    minimumAvailability: selectedMinimumAvailability,
                    monitored: monitored,
                    searchForMovie: searchForMovie,
                    tagIds: selectedTagIds.sorted()
                )

                // Update shared library state optimistically
                LibraryStateManager.shared.addMovieLocally(addedMovie)

                await MainActor.run {
                    isAdding = false
                    isSuccess = true
                    onAdded()
                    // Auto dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    if error.localizedDescription.contains("already") || error.localizedDescription.contains("exists") {
                        errorMessage = "Movie already in library"
                    } else {
                        errorMessage = "Failed to add movie"
                    }
                }
            }
        }
    }

    private func persistCurrentPreferences() {
        guard !isLoadingOptions, !qualityProfiles.isEmpty, !rootFolders.isEmpty else { return }
        let settings = RadarrAddSettings(
            qualityProfileId: selectedQualityProfileId,
            rootFolderPath: selectedRootFolderPath.isEmpty ? "/movies/" : selectedRootFolderPath,
            minimumAvailability: selectedMinimumAvailability,
            monitored: monitored,
            searchForMovie: searchForMovie,
            tagIds: selectedTagIds.sorted()
        )
        AddMediaPreferences.shared.saveRadarr(settings)
    }
}

// MARK: - Quick Add TV Show Sheet

struct QuickAddTVShowSheet: View {
    let show: TrendingTVShow
    let onAdded: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @StateObject private var libraryState = LibraryStateManager.shared

    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var isSuccess = false
    @State private var selectedQualityProfileId: Int = 1
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false

    // Add options state
    @State private var rootFolders: [SonarrRootFolder] = []
    @State private var selectedRootFolderPath: String = ""
    @State private var selectedMonitorOption: MonitorOption = .all
    @State private var monitored: Bool = true
    @State private var monitorNewItems: SonarrNewItemMonitor = .all
    @State private var seriesType: SonarrSeriesType = .standard
    @State private var seasonFolder: Bool = true
    @State private var searchForMissing: Bool = true
    @State private var searchForCutoffUnmet: Bool = false
    @State private var selectedTagIds: Set<Int> = []
    @State private var tags: [MediaTag] = []
    @State private var isLoadingOptions = true

    private var selectedTagSummary: String {
        tagSummary(selectedTagIds: selectedTagIds, tags: tags)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(ColorPalette.textMutedDark)
                .frame(width: 36, height: 5)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Poster and info
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        // Poster
                        CachedAsyncImage(url: show.posterURL, width: 120, height: 180)
                            .cornerRadius(AppRadius.md)

                        // Info
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(show.name)
                                .font(AppTypography.title3())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .lineLimit(3)

                            if let year = show.year {
                                Text("\(year)")
                                    .font(AppTypography.subheadline(.medium))
                                    .foregroundColor(ColorPalette.secondary)
                            }

                            if let rating = show.voteAverage, rating > 0 {
                                HStack(spacing: AppSpacing.xxs) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(ColorPalette.warning)
                                        .font(.system(size: 12))
                                    Text(String(format: "%.1f", rating))
                                        .font(AppTypography.caption1(.medium))
                                        .foregroundColor(ColorPalette.textSecondaryDark)
                                }
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Overview
                    if let overview = show.overview, !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(4)
                    }

                    // Trailer button
                    if isLoadingTrailer {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.textSecondaryDark))
                                .scaleEffect(0.8)
                            Text("Loading trailer...")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                        }
                    } else if let url = trailerURL {
                        Button(action: { openURL(url) }) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "play.fill")
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
                            .cornerRadius(AppRadius.md)
                        }
                    }

                    // Add options section
                    #if os(tvOS)
                    tvShowOptionsSectionTV
                    #else
                    tvShowOptionsSectioniOS
                    #endif

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ColorPalette.error)
                            Text(error)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.error)
                        }
                        .padding()
                        .background(ColorPalette.error.opacity(0.1))
                        .cornerRadius(AppRadius.sm)
                    }

                    // Success message
                    if isSuccess {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorPalette.success)
                            Text("TV Show added to Sonarr!")
                                .font(AppTypography.subheadline(.medium))
                                .foregroundColor(ColorPalette.success)
                        }
                        .padding()
                        .background(ColorPalette.success.opacity(0.1))
                        .cornerRadius(AppRadius.sm)
                    }

                    Spacer(minLength: AppSpacing.lg)

                    // Add button
                    Button(action: addShow) {
                        HStack(spacing: AppSpacing.xs) {
                            if isAdding {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else if isSuccess {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text(isSuccess ? "Added!" : "Add to Sonarr")
                                .font(AppTypography.body(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSuccess ? ColorPalette.success : ColorPalette.primary)
                        .cornerRadius(AppRadius.md)
                    }
                    .disabled(isAdding || isSuccess)

                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }
        }
        .background(ColorPalette.backgroundDark)
        .task {
            // Load trailer
            loadTrailer()
            // Load options
            await loadOptions()
        }
    }

    // MARK: - iOS Options Section

    #if !os(tvOS)
    private var tvShowOptionsSectioniOS: some View {
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
                        ForEach(libraryState.qualityProfiles) { profile in
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

            // Series type picker
            HStack {
                Text("Series Type")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                Picker("Series Type", selection: $seriesType) {
                    ForEach(SonarrSeriesType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(ColorPalette.secondary)
                .disabled(isLoadingOptions)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Monitor option picker
            HStack {
                Text("Monitor")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                Picker("Monitor Option", selection: $selectedMonitorOption) {
                    ForEach(MonitorOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(ColorPalette.secondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Monitor new items picker
            HStack {
                Text("New Episodes")
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                Picker("New Episodes", selection: $monitorNewItems) {
                    ForEach(SonarrNewItemMonitor.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(ColorPalette.secondary)
                .disabled(isLoadingOptions)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            if !tags.isEmpty {
                TagSelectionMenuRow(
                    title: "Tags",
                    selectedLabel: selectedTagSummary,
                    tags: tags,
                    selectedTagIds: $selectedTagIds
                )
            }

            // Monitored toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitored")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Let Sonarr manage this series after adding")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $monitored)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Season folders toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Season Folders")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Organize episodes into season folders")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $seasonFolder)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Search for episodes toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search for Episodes")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Start searching when series is added")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $searchForMissing)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)

            // Search for cutoff unmet toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search Cutoff Unmet")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text("Also search monitored episodes below cutoff")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                Spacer()

                Toggle("", isOn: $searchForCutoffUnmet)
                    .tint(ColorPalette.primary)
                    .labelsHidden()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)
        }
    }
    #endif

    // MARK: - tvOS Options Section

    #if os(tvOS)
    private var tvShowOptionsSectionTV: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Quality profile picker
            QuickAddPickerRow(
                title: "Quality Profile",
                isLoading: isLoadingOptions,
                selectedLabel: libraryState.qualityProfiles.first { $0.id == selectedQualityProfileId }?.name ?? "Select..."
            ) {
                if let currentIndex = libraryState.qualityProfiles.firstIndex(where: { $0.id == selectedQualityProfileId }) {
                    let nextIndex = (currentIndex + 1) % libraryState.qualityProfiles.count
                    selectedQualityProfileId = libraryState.qualityProfiles[nextIndex].id
                } else if let first = libraryState.qualityProfiles.first {
                    selectedQualityProfileId = first.id
                }
            }

            // Root folder picker
            QuickAddPickerRow(
                title: "Root Folder",
                isLoading: isLoadingOptions,
                selectedLabel: rootFolders.first { $0.path == selectedRootFolderPath }?.folderName ?? "Select..."
            ) {
                if let currentIndex = rootFolders.firstIndex(where: { $0.path == selectedRootFolderPath }) {
                    let nextIndex = (currentIndex + 1) % rootFolders.count
                    selectedRootFolderPath = rootFolders[nextIndex].path
                } else if let first = rootFolders.first {
                    selectedRootFolderPath = first.path
                }
            }

            QuickAddPickerRow(
                title: "Series Type",
                isLoading: isLoadingOptions,
                selectedLabel: seriesType.displayName
            ) {
                let allCases = SonarrSeriesType.allCases
                if let currentIndex = allCases.firstIndex(of: seriesType) {
                    let nextIndex = (currentIndex + 1) % allCases.count
                    seriesType = allCases[nextIndex]
                }
            }

            // Monitor option picker
            QuickAddPickerRow(
                title: "Monitor",
                isLoading: false,
                selectedLabel: selectedMonitorOption.displayName
            ) {
                let allCases = MonitorOption.allCases
                if let currentIndex = allCases.firstIndex(of: selectedMonitorOption) {
                    let nextIndex = (currentIndex + 1) % allCases.count
                    selectedMonitorOption = allCases[nextIndex]
                }
            }

            QuickAddPickerRow(
                title: "New Episodes",
                isLoading: isLoadingOptions,
                selectedLabel: monitorNewItems.displayName
            ) {
                let allCases = SonarrNewItemMonitor.allCases
                if let currentIndex = allCases.firstIndex(of: monitorNewItems) {
                    let nextIndex = (currentIndex + 1) % allCases.count
                    monitorNewItems = allCases[nextIndex]
                }
            }

            QuickAddToggleRow(
                title: "Monitored",
                subtitle: "Let Sonarr manage this series after adding",
                isOn: $monitored
            )

            QuickAddToggleRow(
                title: "Season Folders",
                subtitle: "Organize episodes into season folders",
                isOn: $seasonFolder
            )

            // Search for episodes toggle
            QuickAddToggleRow(
                title: "Search for Episodes",
                subtitle: "Start searching when series is added",
                isOn: $searchForMissing
            )

            QuickAddToggleRow(
                title: "Search Cutoff Unmet",
                subtitle: "Also search monitored episodes below cutoff",
                isOn: $searchForCutoffUnmet
            )
        }
    }
    #endif

    private func loadOptions() async {
        do {
            // Load quality profiles and root folders in parallel
            async let foldersTask = SonarrService.shared.fetchRootFolders()
            async let tagsTask: [MediaTag] = (try? await SonarrService.shared.fetchTags()) ?? []
            await libraryState.loadQualityProfiles()
            let (folders, fetchedTags) = try await (foldersTask, tagsTask)

            await MainActor.run {
                rootFolders = folders
                tags = fetchedTags

                let preferences = AddMediaPreferences.shared.sonarrSettings(
                    profiles: libraryState.qualityProfiles,
                    rootFolders: folders,
                    tags: fetchedTags
                )
                selectedQualityProfileId = preferences.qualityProfileId
                selectedRootFolderPath = preferences.rootFolderPath
                selectedMonitorOption = preferences.monitorOption
                monitored = preferences.monitored
                monitorNewItems = preferences.monitorNewItems
                seriesType = preferences.seriesType
                seasonFolder = preferences.seasonFolder
                searchForMissing = preferences.searchForMissingEpisodes
                searchForCutoffUnmet = preferences.searchForCutoffUnmetEpisodes
                selectedTagIds = Set(preferences.tagIds)

                isLoadingOptions = false
            }
        } catch {
            await MainActor.run {
                isLoadingOptions = false
            }
        }
    }

    private func loadTrailer() {
        isLoadingTrailer = true
        Task {
            let url = await TMDBService.shared.getTVShowTrailerURLByTMDBId(tmdbId: show.id)
            await MainActor.run {
                trailerURL = url
                isLoadingTrailer = false
            }
        }
    }

    private func addShow() {
        guard !isLoadingOptions, !libraryState.qualityProfiles.isEmpty, !rootFolders.isEmpty else {
            errorMessage = "Load a quality profile and root folder before adding this show."
            return
        }

        isAdding = true
        errorMessage = nil

        Task {
            do {
                persistCurrentPreferences()
                // Use cached search - the CacheManager will deduplicate if same search is in progress
                let results = try await SonarrService.shared.searchShows(term: show.name)

                // Find the best matching show (by year if available)
                let showLookup: TVShowLookup
                if let year = show.year {
                    guard let match = results.first(where: { $0.year == year }) ?? results.first else {
                        throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Show not found in Sonarr"])
                    }
                    showLookup = match
                } else {
                    guard let first = results.first else {
                        throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Show not found in Sonarr"])
                    }
                    showLookup = first
                }

                // Add to Sonarr with selected options
                let addedShow = try await SonarrService.shared.addShow(
                    show: showLookup,
                    monitorOption: selectedMonitorOption,
                    qualityProfileId: selectedQualityProfileId,
                    rootFolderPath: selectedRootFolderPath.isEmpty ? "/tv/" : selectedRootFolderPath,
                    monitored: monitored,
                    monitorNewItems: monitorNewItems,
                    seriesType: seriesType,
                    seasonFolder: seasonFolder,
                    searchForMissingEpisodes: searchForMissing,
                    searchForCutoffUnmetEpisodes: searchForCutoffUnmet,
                    tagIds: selectedTagIds.sorted()
                )

                // Update shared library state optimistically
                LibraryStateManager.shared.addShowLocally(addedShow)

                await MainActor.run {
                    isAdding = false
                    isSuccess = true
                    onAdded()
                    // Auto dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    if error.localizedDescription.contains("already") || error.localizedDescription.contains("exists") {
                        errorMessage = "Show already in library"
                    } else {
                        errorMessage = "Failed to add show"
                    }
                }
            }
        }
    }

    private func persistCurrentPreferences() {
        guard !isLoadingOptions, !libraryState.qualityProfiles.isEmpty, !rootFolders.isEmpty else { return }
        let settings = SonarrAddSettings(
            qualityProfileId: selectedQualityProfileId,
            rootFolderPath: selectedRootFolderPath.isEmpty ? "/tv/" : selectedRootFolderPath,
            monitorOption: selectedMonitorOption,
            monitored: monitored,
            monitorNewItems: monitorNewItems,
            seriesType: seriesType,
            seasonFolder: seasonFolder,
            searchForMissingEpisodes: searchForMissing,
            searchForCutoffUnmetEpisodes: searchForCutoffUnmet,
            tagIds: selectedTagIds.sorted()
        )
        AddMediaPreferences.shared.saveSonarr(settings)
    }
}

#Preview("Movie") {
    QuickAddMovieSheet(
        movie: TrendingMovie(
            id: 12345,
            title: "The Dark Knight",
            overview: "When the menace known as the Joker wreaks havoc and chaos on the people of Gotham, Batman must accept one of the greatest psychological and physical tests of his ability to fight injustice.",
            posterPath: "/qJ2tW6WMUDux911r6m7haRef0WH.jpg",
            backdropPath: nil,
            releaseDate: "2008-07-18",
            voteAverage: 8.5,
            genreIds: [28, 80, 18]
        ),
        onAdded: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("TV Show") {
    QuickAddTVShowSheet(
        show: TrendingTVShow(
            id: 12345,
            name: "Breaking Bad",
            overview: "A high school chemistry teacher diagnosed with inoperable lung cancer turns to manufacturing and selling methamphetamine in order to secure his family's future.",
            posterPath: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
            backdropPath: nil,
            firstAirDate: "2008-01-20",
            voteAverage: 8.9,
            genreIds: [18, 80]
        ),
        onAdded: {}
    )
    .preferredColorScheme(.dark)
}

// MARK: - tvOS Helper Components

#if os(tvOS)
struct QuickAddPickerRow: View {
    let title: String
    let isLoading: Bool
    let selectedLabel: String
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.0)
                    .tint(ColorPalette.secondary)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    Text(selectedLabel)
                        .font(.system(size: 22))
                        .foregroundColor(ColorPalette.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 18))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isFocused ? ColorPalette.cardBackgroundElevatedDark : ColorPalette.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isFocused ? ColorPalette.secondary : ColorPalette.divider, lineWidth: isFocused ? 3 : 1)
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            onTap()
        }
        .disabled(isLoading)
    }
}

struct QuickAddToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 18))
                    .foregroundColor(Color.white.opacity(0.7))
            }

            Spacer()

            // Toggle indicator
            ZStack {
                Capsule()
                    .fill(isOn ? ColorPalette.secondary : Color.gray.opacity(0.3))
                    .frame(width: 60, height: 34)

                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .offset(x: isOn ? 12 : -12)
                    .animation(.easeInOut(duration: 0.2), value: isOn)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isFocused ? ColorPalette.cardBackgroundElevatedDark : ColorPalette.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isFocused ? ColorPalette.secondary : ColorPalette.divider, lineWidth: isFocused ? 3 : 1)
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            isOn.toggle()
        }
    }
}
#endif
