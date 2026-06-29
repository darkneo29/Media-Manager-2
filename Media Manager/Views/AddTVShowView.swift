import SwiftUI
import Combine

struct AddTVShowView: View {
    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @State private var searchResults: [TVShowLookup] = []
    @State private var isSearching = false
    @State private var addingShowId: Int?
    @State private var errorMessage: String?
    @State private var selectedMonitorOption: MonitorOption = .all
    @State private var monitored: Bool = true
    @State private var monitorNewItems: SonarrNewItemMonitor = .all
    @State private var seriesType: SonarrSeriesType = .standard
    @State private var seasonFolder: Bool = true
    @State private var searchForMissing: Bool = true
    @State private var searchForCutoffUnmet: Bool = false
    @State private var qualityProfiles: [QualityProfile] = []
    @State private var rootFolders: [SonarrRootFolder] = []
    @State private var selectedQualityProfileId: Int = 6
    @State private var selectedRootFolderPath: String = ""
    @State private var selectedTagIds: Set<Int> = []
    @State private var tags: [MediaTag] = []
    @State private var isLoadingOptions = true
    @State private var optionsErrorMessage: String?

    // Debouncing support
    @State private var searchTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 300_000_000 // 300ms in nanoseconds
    @FocusState private var isSearchFieldFocused: Bool

    @Environment(\.dismiss) var dismiss

    private var canAddShow: Bool {
        !isLoadingOptions && optionsErrorMessage == nil && !qualityProfiles.isEmpty && !rootFolders.isEmpty
    }

    private var selectedTagSummary: String {
        tagSummary(selectedTagIds: selectedTagIds, tags: tags)
    }

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle("Add TV Show")
        .navBarTitleDisplayMode(.inline)
        #if !os(tvOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .onAppear {
            loadOptions()
        }
        .onDisappear {
            persistCurrentPreferences()
            if let show = pendingShow {
                pendingShow = nil
                navigationPath.append(show)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ColorPalette.textMutedDark)
                TextField("Search for TV show...", text: $searchText)
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
    }

    #if !os(tvOS)
    private var iOSContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchBar
                iOSOptionsSection
                optionsErrorSection
                Divider()
                    .background(ColorPalette.divider)
                iOSSearchContent
            }
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

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

            // Search for missing toggle
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
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
    }

    @ViewBuilder
    private var iOSSearchContent: some View {
        if isSearching {
            loadingStateView
        } else if let error = errorMessage {
            stateView(
                icon: "exclamationmark.triangle",
                iconColor: ColorPalette.error,
                title: error,
                subtitle: nil
            )
        } else if searchResults.isEmpty && !searchText.isEmpty {
            stateView(
                icon: "tv",
                iconColor: ColorPalette.textMutedDark,
                title: "No results found",
                subtitle: "Try a different search term"
            )
        } else if searchResults.isEmpty {
            stateView(
                icon: "magnifyingglass",
                iconColor: ColorPalette.textMutedDark,
                title: "Search for TV shows",
                subtitle: "Find shows to add to your library"
            )
        } else {
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(searchResults) { show in
                    TVShowSearchResultCard(show: show, isAdding: addingShowId == show.tvdbId) {
                        addShow(show)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
        }
    }
    #endif

    #if os(tvOS)
    private var tvOSContent: some View {
        VStack(spacing: 0) {
            searchBar
            tvOSOptionsSection
            optionsErrorSection
            Divider()
                .background(ColorPalette.divider)
            tvOSSearchContent
        }
    }

    @ViewBuilder
    private var tvOSSearchContent: some View {
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
        } else if searchResults.isEmpty && !searchText.isEmpty {
            Spacer()
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "tv")
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
        } else if searchResults.isEmpty {
            Spacer()
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(ColorPalette.textMutedDark)
                Text("Search for TV shows")
                    .font(AppTypography.headline())
                    .foregroundColor(ColorPalette.textSecondaryDark)
                Text("Find shows to add to your library")
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(searchResults) { show in
                        TVShowSearchResultCard(show: show, isAdding: addingShowId == show.tvdbId) {
                            addShow(show)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
        }
    }
    #endif

    @ViewBuilder
    private var optionsErrorSection: some View {
        if let optionsErrorMessage {
            optionErrorBanner(message: optionsErrorMessage) {
                loadOptions(forceRefresh: true)
            }
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(ColorPalette.primary)
            Text("Searching...")
                .font(AppTypography.caption1())
                .foregroundColor(ColorPalette.textMutedDark)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding()
    }

    private func stateView(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
            Text(title)
                .font(subtitle == nil ? AppTypography.subheadline() : AppTypography.headline())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding()
    }

    #if os(tvOS)
    private var tvOSOptionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            TVAddMoviePickerRow(
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

            TVAddMoviePickerRow(
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

            TVAddMoviePickerRow(
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

            TVAddMoviePickerRow(
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

            TVAddMoviePickerRow(
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

            if !tags.isEmpty {
                TVTagSelectionMenuRow(
                    title: "Tags",
                    selectedLabel: selectedTagSummary,
                    tags: tags,
                    selectedTagIds: $selectedTagIds
                )
            }

            TVAddMovieToggleRow(
                title: "Monitored",
                subtitle: "Let Sonarr manage this series after adding",
                isOn: $monitored
            )

            TVAddMovieToggleRow(
                title: "Season Folders",
                subtitle: "Organize episodes into season folders",
                isOn: $seasonFolder
            )

            TVAddMovieToggleRow(
                title: "Search for Episodes",
                subtitle: "Start searching when series is added",
                isOn: $searchForMissing
            )

            TVAddMovieToggleRow(
                title: "Search Cutoff Unmet",
                subtitle: "Also search monitored episodes below cutoff",
                isOn: $searchForCutoffUnmet
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
                async let profilesTask = SonarrService.shared.fetchQualityProfiles(forceRefresh: forceRefresh)
                async let foldersTask = SonarrService.shared.fetchRootFolders(forceRefresh: forceRefresh)
                async let tagsTask: [MediaTag] = (try? await SonarrService.shared.fetchTags(forceRefresh: forceRefresh)) ?? []

                let (profiles, folders, fetchedTags) = try await (profilesTask, foldersTask, tagsTask)

                await MainActor.run {
                    qualityProfiles = profiles
                    rootFolders = folders
                    tags = fetchedTags
                    optionsErrorMessage = nil

                    let preferences = AddMediaPreferences.shared.sonarrSettings(
                        profiles: profiles,
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
                    optionsErrorMessage = "Could not load Sonarr profiles or root folders: \(error.localizedDescription)"
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
                let results = try await SonarrService.shared.searchShows(term: query)
                await MainActor.run {
                    searchResults = results
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

    @State private var pendingShow: TVShow?

    private func addShow(_ show: TVShowLookup) {
        guard canAddShow else {
            errorMessage = optionsErrorMessage ?? "Load a quality profile and root folder before adding a show."
            return
        }

        addingShowId = show.tvdbId
        Task {
            do {
                persistCurrentPreferences()
                let addedShow = try await SonarrService.shared.addShow(
                    show: show,
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
                await MainActor.run {
                    LibraryStateManager.shared.addShowLocally(addedShow)
                    pendingShow = addedShow
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add show: \(error.localizedDescription)"
                    addingShowId = nil
                }
            }
        }
    }

    private func persistCurrentPreferences() {
        guard !isLoadingOptions, !qualityProfiles.isEmpty, !rootFolders.isEmpty else { return }
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

struct TVShowSearchResultCard: View {
    let show: TVShowLookup
    let isAdding: Bool
    let onAdd: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false
    @State private var trailerUnavailable = false

    private var posterURL: URL? {
        show.images?.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return SonarrService.shared.imageURL(for: image.url)
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
                    Text(show.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.xs) {
                        Text(String(show.year))
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(ColorPalette.secondary)

                        if show.seasonCount > 0 {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text("\(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textMutedDark)
                        }

                        if let network = show.network, !network.isEmpty {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text(network)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .lineLimit(1)
                        }
                    }

                    if let overview = show.overview, !overview.isEmpty {
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
            let url = await TMDBService.shared.getTVShowTrailerURL(tvdbId: show.tvdbId)

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

#Preview {
    NavigationStack {
        AddTVShowView(navigationPath: .constant(NavigationPath()))
    }
    .preferredColorScheme(.dark)
}
