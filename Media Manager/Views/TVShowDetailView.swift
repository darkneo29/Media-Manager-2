import SwiftUI

struct TVShowDetailView: View {
    @State private var show: TVShow
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @ObservedObject private var releaseRadar = ReleaseRadarService.shared
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var isDeleting = false

    // File management state
    @State private var episodeFiles: [EpisodeFile] = []
    @State private var isLoadingFiles = true
    @State private var isDeletingFile = false
    @State private var isSearching = false
    @State private var showingDeleteFileAlert = false
    @State private var fileToDelete: EpisodeFile?
    @State private var expandedSeasons: Set<Int> = []

    // Episode management state
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = true
    @State private var expandedEpisodeSeasons: Set<Int> = []
    @State private var searchingEpisodeId: Int?
    @State private var updatingEpisodeId: Int?
    @State private var selectedReleaseEpisode: Episode?

    // View mode: files or episodes
    @State private var showEpisodes = true

    // Trailer state
    @State private var trailerURL: URL?
    @State private var isLoadingTrailer = false

    // Toast state
    @State private var showSearchToast = false

    @State private var tags: [MediaTag] = []

    /// Check if we're on tvOS
    private var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    init(show: TVShow) {
        _show = State(initialValue: show)
    }

    private var posterURL: URL? {
        show.images.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return SonarrService.shared.imageURL(for: image.url)
            }
    }

    private var fanartURL: URL? {
        show.images.first(where: { $0.coverType == "fanart" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return SonarrService.shared.imageURL(for: image.url)
            }
    }

    private var managementLocation: String? {
        show.rootFolderPath ?? show.path
    }

    private var managementTags: String? {
        let tagIds = show.tags ?? []
        guard !tagIds.isEmpty else { return nil }
        if tags.isEmpty {
            return tagIds.map { "#\($0)" }.joined(separator: ", ")
        }
        let labels = tags.filter { tagIds.contains($0.id) }.map(\.label)
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    private var hasManagementDetails: Bool {
        managementLocation != nil ||
        show.seriesTypeDisplayName != nil ||
        show.monitorNewItemsDisplayName != nil ||
        show.seasonFolder != nil ||
        managementTags != nil
    }

    /// Group episode files by season
    private var filesBySeason: [SeasonFiles] {
        let grouped = Dictionary(grouping: episodeFiles) { $0.seasonNumber }
        return grouped.map { SeasonFiles(seasonNumber: $0.key, files: $0.value) }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// Total size of all episode files
    private var totalSize: String {
        let total = episodeFiles.reduce(0) { $0 + $1.size }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }

    /// Group episodes by season
    private var episodesBySeason: [(seasonNumber: Int, episodes: [Episode])] {
        let grouped = Dictionary(grouping: episodes) { $0.seasonNumber }
        return grouped.map { (seasonNumber: $0.key, episodes: $0.value.sorted { $0.episodeNumber < $1.episodeNumber }) }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// Count of missing episodes
    private var missingEpisodesCount: Int {
        episodes.filter { $0.hasAired && !$0.hasFile && $0.monitored }.count
    }

    /// Count of downloaded episodes
    private var downloadedEpisodesCount: Int {
        episodes.filter { $0.hasFile }.count
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

                        // Show info
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            Text(show.title)
                                .font(AppTypography.largeTitle())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: AppSpacing.md) {
                                MetaPill(text: String(show.year), icon: "calendar")
                                MetaPill(text: "\(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")", icon: "number")
                                MetaPill(text: "\(show.episodeCount) Ep", icon: "play.rectangle")
                                MetaPill(
                                    text: show.status.capitalized,
                                    icon: show.status == "ended" ? "checkmark.circle.fill" : "clock.badge.checkmark"
                                )
                            }

                            // Network
                            if let network = show.network, !network.isEmpty {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(ColorPalette.secondary)
                                        .font(.system(size: 18))
                                    Text(network)
                                        .font(AppTypography.body(.medium))
                                        .foregroundColor(ColorPalette.secondary)
                                }
                            }

                            // Monitored status
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: show.monitored ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(show.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                Text(show.monitored ? "Monitored" : "Not Monitored")
                                    .font(AppTypography.body(.medium))
                                    .foregroundColor(show.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
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
                            Text(show.overview ?? "No overview available.")
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
                            Text(show.title)
                                .font(AppTypography.title2())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.center)

                            HStack(spacing: AppSpacing.sm) {
                                MetaPill(text: String(show.year), icon: "calendar")

                                MetaPill(text: "\(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")", icon: "number")

                                MetaPill(text: "\(show.episodeCount) Ep", icon: "play.rectangle")

                                MetaPill(
                                    text: show.status.capitalized,
                                    icon: show.status == "ended" ? "checkmark.circle.fill" : "clock.badge.checkmark"
                                )
                            }

                            // Network
                            if let network = show.network, !network.isEmpty {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(ColorPalette.secondary)
                                        .font(.system(size: 12))
                                    Text(network)
                                        .font(AppTypography.caption1(.medium))
                                        .foregroundColor(ColorPalette.secondary)
                                }
                            }

                            // Monitored status
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: show.monitored ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(show.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                Text(show.monitored ? "Monitored" : "Not Monitored")
                                    .font(AppTypography.caption1(.medium))
                                    .foregroundColor(show.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
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

                            Text(show.overview ?? "No overview available.")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        #endif

                        if hasManagementDetails {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                SectionTitle(text: "Management")

                                VStack(spacing: AppSpacing.xs) {
                                    if let location = managementLocation {
                                        ManagementInfoRow(label: "Location", value: location, icon: "folder")
                                    }
                                    if let seriesType = show.seriesTypeDisplayName {
                                        ManagementInfoRow(label: "Series Type", value: seriesType, icon: "rectangle.stack")
                                    }
                                    if let monitorNewItems = show.monitorNewItemsDisplayName {
                                        ManagementInfoRow(label: "New Episodes", value: monitorNewItems, icon: "sparkles.tv")
                                    }
                                    if let seasonFolder = show.seasonFolder {
                                        ManagementInfoRow(label: "Season Folders", value: seasonFolder ? "On" : "Off", icon: "folder.badge.gearshape")
                                    }
                                    if let managementTags {
                                        ManagementInfoRow(label: "Tags", value: managementTags, icon: "tag")
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }

                        // Episodes/Files section
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            // Section header with toggle
                            HStack {
                                SectionTitle(text: "Episodes")
                                Spacer()
                                // Episode stats
                                if !episodes.isEmpty {
                                    HStack(spacing: AppSpacing.xs) {
                                        Text("\(downloadedEpisodesCount)/\(episodes.filter { $0.hasAired }.count)")
                                            .font(AppTypography.caption1(.semibold))
                                            .foregroundColor(ColorPalette.success)
                                        if missingEpisodesCount > 0 {
                                            Text("• \(missingEpisodesCount) missing")
                                                .font(AppTypography.caption1())
                                                .foregroundColor(ColorPalette.error)
                                        }
                                    }
                                }
                            }

                            // Segmented control
                            Picker("View", selection: $showEpisodes) {
                                Text("Episodes").tag(true)
                                Text("Files").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, AppSpacing.xs)

                            if showEpisodes {
                                // Episodes view
                                if isLoadingEpisodes {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading episodes...")
                                            .font(AppTypography.caption1())
                                            .foregroundColor(ColorPalette.textMutedDark)
                                        Spacer()
                                    }
                                    .padding(.vertical, AppSpacing.md)
                                } else if episodes.isEmpty {
                                    Text("No episodes found")
                                        .font(AppTypography.subheadline())
                                        .foregroundColor(ColorPalette.textMutedDark)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppSpacing.md)
                                } else {
                                    // Seasons with episodes
                                    ForEach(episodesBySeason, id: \.seasonNumber) { season in
                                        EpisodeSeasonSection(
                                            seasonNumber: season.seasonNumber,
                                            episodes: season.episodes,
                                            isExpanded: expandedEpisodeSeasons.contains(season.seasonNumber),
                                            onToggle: {
                                                if expandedEpisodeSeasons.contains(season.seasonNumber) {
                                                    expandedEpisodeSeasons.remove(season.seasonNumber)
                                                } else {
                                                    expandedEpisodeSeasons.insert(season.seasonNumber)
                                                }
                                            },
                                            onSearchEpisode: { episode in
                                                searchForEpisode(episode)
                                            },
                                            onManualSearchEpisode: { episode in
                                                selectedReleaseEpisode = episode
                                            },
                                            onToggleEpisodeMonitoring: { episode in
                                                toggleEpisodeMonitoring(episode)
                                            },
                                            onSetSeasonMonitoring: { episodes, monitored in
                                                setSeasonMonitoring(episodes: episodes, monitored: monitored)
                                            },
                                            searchingEpisodeId: searchingEpisodeId,
                                            updatingEpisodeId: updatingEpisodeId
                                        )
                                    }

                                    // Search for missing episodes button
                                    if missingEpisodesCount > 0 {
                                        Button(action: { searchForShow() }) {
                                            HStack {
                                                if isSearching {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                } else {
                                                    Image(systemName: "magnifyingglass")
                                                }
                                                Text(isSearching ? "Searching..." : "Search for All Missing Episodes")
                                            }
                                            .font(AppTypography.subheadline(.medium))
                                            .foregroundColor(ColorPalette.primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, AppSpacing.sm)
                                            .background(ColorPalette.primary.opacity(0.1))
                                            .cornerRadius(AppRadius.md)
                                        }
                                        .disabled(isSearching)
                                        .padding(.top, AppSpacing.xs)
                                    }
                                }
                            } else {
                                // Files view
                                if isLoadingFiles {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading files...")
                                            .font(AppTypography.caption1())
                                            .foregroundColor(ColorPalette.textMutedDark)
                                        Spacer()
                                    }
                                    .padding(.vertical, AppSpacing.md)
                                } else if episodeFiles.isEmpty {
                                    NoFileCard(
                                        message: "No episode files downloaded yet. The show is being monitored and episodes will download when available.",
                                        onSearch: { searchForShow() },
                                        isSearching: isSearching
                                    )
                                } else {
                                    // File stats
                                    Text("\(episodeFiles.count) files • \(totalSize)")
                                        .font(AppTypography.caption1())
                                        .foregroundColor(ColorPalette.textMutedDark)
                                        .padding(.bottom, AppSpacing.xs)

                                    // Seasons with collapsible file lists
                                    ForEach(filesBySeason) { season in
                                        SeasonFilesSection(
                                            season: season,
                                            isExpanded: expandedSeasons.contains(season.seasonNumber),
                                            onToggle: {
                                                if expandedSeasons.contains(season.seasonNumber) {
                                                    expandedSeasons.remove(season.seasonNumber)
                                                } else {
                                                    expandedSeasons.insert(season.seasonNumber)
                                                }
                                            },
                                            onDeleteFile: { file in
                                                fileToDelete = file
                                                showingDeleteFileAlert = true
                                            },
                                            isDeletingFile: isDeletingFile,
                                            fileToDelete: fileToDelete
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // Action buttons
                        VStack(spacing: AppSpacing.sm) {
                            Button {
                                releaseRadar.toggleFollow(show: show)
                                syncWidgetReleaseRadar()
                            } label: {
                                HStack {
                                    Image(systemName: releaseRadar.isFollowing(show: show) ? "star.fill" : "star")
                                    Text(releaseRadar.isFollowing(show: show) ? "Following in Release Radar" : "Follow in Release Radar")
                                }
                                .font(AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(ColorPalette.secondary)
                                .cornerRadius(AppRadius.md)
                            }

                            Button {
                                showingEditSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit Show")
                                }
                                .font(AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(ColorPalette.primary)
                                .cornerRadius(AppRadius.md)
                            }

                            Button {
                                showingDeleteAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Show")
                                }
                                .font(AppTypography.headline())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(ColorPalette.error)
                                .cornerRadius(AppRadius.md)
                            }
                            .disabled(isDeleting)
                            .opacity(isDeleting ? 0.6 : 1)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.md)
                    }
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
        }
        .navigationTitle("Details")
        .navBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(show.title)?", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
            Button("Remove from Sonarr Only", role: .destructive) {
                deleteShow(deleteFiles: false, addImportExclusion: false)
            }
            Button("Remove and Delete Files", role: .destructive) {
                deleteShow(deleteFiles: true, addImportExclusion: false)
            }
            Button("Remove, Delete Files, and Exclude", role: .destructive) {
                deleteShow(deleteFiles: true, addImportExclusion: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether to keep files on disk or delete them.")
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            refreshShow()
        }) {
            EditTVShowView(show: show)
        }
        .alert("Delete Episode File?", isPresented: $showingDeleteFileAlert) {
            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let file = fileToDelete {
                    deleteEpisodeFile(file)
                }
            }
        } message: {
            Text("Are you sure you want to delete this episode file? The episode will remain in your library but the file will be removed from disk.")
        }
        .sheet(item: $selectedReleaseEpisode) { episode in
            ReleaseSearchSheet(
                title: episode.displayTitle,
                loadReleases: { try await SonarrService.shared.fetchEpisodeReleases(episodeId: episode.id) },
                grabRelease: { try await SonarrService.shared.grabRelease($0) }
            )
        }
        .task {
            loadEpisodeFiles()
            loadEpisodes()
            loadTrailer()
            loadTags()
        }
        .toast(
            isShowing: $showSearchToast,
            message: "Search started! Sonarr is looking for episodes.",
            style: .success
        )
    }

    // MARK: - Trailer Loading

    private func loadTrailer() {
        guard let tvdbId = show.tvdbId else { return }
        isLoadingTrailer = true
        Task {
            let url = await TMDBService.shared.getTVShowTrailerURL(tvdbId: tvdbId)
            await MainActor.run {
                trailerURL = url
                isLoadingTrailer = false
            }
        }
    }

    private func loadTags() {
        guard !(show.tags ?? []).isEmpty else { return }
        Task {
            let fetchedTags = (try? await SonarrService.shared.fetchTags()) ?? []
            await MainActor.run {
                tags = fetchedTags
            }
        }
    }

    // MARK: - Episode Management

    private func loadEpisodes() {
        isLoadingEpisodes = true
        Task {
            do {
                let eps = try await SonarrService.shared.fetchEpisodes(seriesId: show.id)
                await MainActor.run {
                    episodes = eps
                    isLoadingEpisodes = false
                }
            } catch {
                await MainActor.run {
                    isLoadingEpisodes = false
                }
            }
        }
    }

    private func searchForEpisode(_ episode: Episode) {
        searchingEpisodeId = episode.id
        Task {
            do {
                try await SonarrService.shared.searchForEpisode(episodeId: episode.id)
                await MainActor.run {
                    searchingEpisodeId = nil
                    showSearchToast = true
                }
            } catch {
                await MainActor.run {
                    searchingEpisodeId = nil
                }
            }
        }
    }

    private func toggleEpisodeMonitoring(_ episode: Episode) {
        updatingEpisodeId = episode.id
        Task {
            do {
                try await SonarrService.shared.updateEpisode(episodeId: episode.id, monitored: !episode.monitored)
                await MainActor.run {
                    if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
                        var updated = episodes[index]
                        updated = Episode(
                            id: updated.id,
                            seriesId: updated.seriesId,
                            tvdbId: updated.tvdbId,
                            episodeFileId: updated.episodeFileId,
                            seasonNumber: updated.seasonNumber,
                            episodeNumber: updated.episodeNumber,
                            title: updated.title,
                            airDate: updated.airDate,
                            airDateUtc: updated.airDateUtc,
                            overview: updated.overview,
                            hasFile: updated.hasFile,
                            monitored: !updated.monitored,
                            absoluteEpisodeNumber: updated.absoluteEpisodeNumber,
                            sceneAbsoluteEpisodeNumber: updated.sceneAbsoluteEpisodeNumber,
                            sceneEpisodeNumber: updated.sceneEpisodeNumber,
                            sceneSeasonNumber: updated.sceneSeasonNumber,
                            unverifiedSceneNumbering: updated.unverifiedSceneNumbering,
                            series: updated.series
                        )
                        episodes[index] = updated
                    }
                    updatingEpisodeId = nil
                }
            } catch {
                await MainActor.run {
                    updatingEpisodeId = nil
                }
            }
        }
    }

    private func setSeasonMonitoring(episodes seasonEpisodes: [Episode], monitored: Bool) {
        Task {
            do {
                try await SonarrService.shared.updateEpisodes(seasonEpisodes, monitored: monitored)
                await MainActor.run {
                    let ids = Set(seasonEpisodes.map(\.id))
                    episodes = episodes.map { episode in
                        guard ids.contains(episode.id) else { return episode }
                        return Episode(
                            id: episode.id,
                            seriesId: episode.seriesId,
                            tvdbId: episode.tvdbId,
                            episodeFileId: episode.episodeFileId,
                            seasonNumber: episode.seasonNumber,
                            episodeNumber: episode.episodeNumber,
                            title: episode.title,
                            airDate: episode.airDate,
                            airDateUtc: episode.airDateUtc,
                            overview: episode.overview,
                            hasFile: episode.hasFile,
                            monitored: monitored,
                            absoluteEpisodeNumber: episode.absoluteEpisodeNumber,
                            sceneAbsoluteEpisodeNumber: episode.sceneAbsoluteEpisodeNumber,
                            sceneEpisodeNumber: episode.sceneEpisodeNumber,
                            sceneSeasonNumber: episode.sceneSeasonNumber,
                            unverifiedSceneNumbering: episode.unverifiedSceneNumbering,
                            series: episode.series
                        )
                    }
                }
            } catch {
                #if DEBUG
                print("Error updating season monitoring: \(error)")
                #endif
            }
        }
    }

    // MARK: - File Management

    private func loadEpisodeFiles() {
        isLoadingFiles = true
        Task {
            do {
                let files = try await SonarrService.shared.fetchEpisodeFiles(seriesId: show.id)
                await MainActor.run {
                    episodeFiles = files
                    isLoadingFiles = false
                }
            } catch {
                #if DEBUG
                print("Error loading episode files: \(error)")
                #endif
                await MainActor.run {
                    isLoadingFiles = false
                }
            }
        }
    }

    private func deleteEpisodeFile(_ file: EpisodeFile) {
        isDeletingFile = true
        Task {
            do {
                try await SonarrService.shared.deleteEpisodeFile(id: file.id, seriesId: show.id)
                await MainActor.run {
                    episodeFiles.removeAll { $0.id == file.id }
                    isDeletingFile = false
                    fileToDelete = nil
                }
            } catch {
                #if DEBUG
                print("Error deleting episode file: \(error)")
                #endif
                await MainActor.run {
                    isDeletingFile = false
                    fileToDelete = nil
                }
            }
        }
    }

    private func searchForShow() {
        isSearching = true
        Task {
            do {
                try await SonarrService.shared.searchForShow(seriesId: show.id)
                await MainActor.run {
                    isSearching = false
                    withAnimation {
                        showSearchToast = true
                    }
                }
            } catch {
                #if DEBUG
                print("Error searching for show: \(error)")
                #endif
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }

    private func deleteShow(deleteFiles: Bool, addImportExclusion: Bool) {
        isDeleting = true
        Task {
            do {
                try await SonarrService.shared.deleteShow(
                    id: show.id,
                    deleteFiles: deleteFiles,
                    addImportExclusion: addImportExclusion
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("Error deleting show: \(error)")
                #endif
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }

    private func refreshShow() {
        Task {
            do {
                let shows = try await SonarrService.shared.fetchShows(forceRefresh: true)
                if let updatedShow = shows.first(where: { $0.id == show.id }) {
                    await MainActor.run {
                        show = updatedShow
                    }
                }
            } catch {
                #if DEBUG
                print("Error refreshing show: \(error)")
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

// MARK: - Season Files Section Component

struct SeasonFilesSection: View {
    let season: SeasonFiles
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDeleteFile: (EpisodeFile) -> Void
    let isDeletingFile: Bool
    let fileToDelete: EpisodeFile?

    var body: some View {
        VStack(spacing: 0) {
            // Season header (tappable to expand/collapse)
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ColorPalette.textMutedDark)
                        .frame(width: 20)

                    Text("Season \(season.seasonNumber)")
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    // File count and size
                    Text("\(season.files.count) files • \(season.formattedTotalSize)")
                        .font(AppTypography.caption1())
                        .foregroundColor(ColorPalette.textMutedDark)
                }
                .padding(AppSpacing.sm)
                .background(ColorPalette.cardBackgroundDark)
                .cornerRadius(AppRadius.sm)
            }
            .buttonStyle(.plain)

            // Episode files (shown when expanded)
            if isExpanded {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(season.files.sorted { $0.fileName < $1.fileName }) { file in
                        EpisodeFileCard(
                            file: file,
                            onDelete: { onDeleteFile(file) },
                            isDeleting: isDeletingFile && fileToDelete?.id == file.id
                        )
                    }
                }
                .padding(.top, AppSpacing.xs)
                .padding(.leading, AppSpacing.lg)
            }
        }
    }
}

// MARK: - Episode Season Section Component

struct EpisodeSeasonSection: View {
    let seasonNumber: Int
    let episodes: [Episode]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSearchEpisode: (Episode) -> Void
    let onManualSearchEpisode: (Episode) -> Void
    let onToggleEpisodeMonitoring: (Episode) -> Void
    let onSetSeasonMonitoring: ([Episode], Bool) -> Void
    let searchingEpisodeId: Int?
    let updatingEpisodeId: Int?

    private var displayName: String {
        seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
    }

    private var downloadedCount: Int {
        episodes.filter { $0.hasFile }.count
    }

    private var airedCount: Int {
        episodes.filter { $0.hasAired }.count
    }

    private var missingCount: Int {
        episodes.filter { $0.hasAired && !$0.hasFile && $0.monitored }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Season header (tappable to expand/collapse)
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ColorPalette.textMutedDark)
                        .frame(width: 20)

                    Text(displayName)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    // Episode stats
                    HStack(spacing: AppSpacing.xs) {
                        Menu {
                            Button("Monitor Season") {
                                onSetSeasonMonitoring(episodes, true)
                            }
                            Button("Unmonitor Season") {
                                onSetSeasonMonitoring(episodes, false)
                            }
                        } label: {
                            Image(systemName: "eye.circle")
                                .font(.system(size: 14))
                                .foregroundColor(ColorPalette.secondary)
                        }

                        Text("\(downloadedCount)/\(airedCount)")
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(downloadedCount == airedCount ? ColorPalette.success : ColorPalette.textSecondaryDark)

                        if missingCount > 0 {
                            Circle()
                                .fill(ColorPalette.error)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(AppSpacing.sm)
                .background(ColorPalette.cardBackgroundDark)
                .cornerRadius(AppRadius.sm)
            }
            .buttonStyle(.plain)

            // Episodes (shown when expanded)
            if isExpanded {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(episodes) { episode in
                        EpisodeCard(
                            episode: episode,
                            onSearch: { onSearchEpisode(episode) },
                            onManualSearch: { onManualSearchEpisode(episode) },
                            onToggleMonitoring: { onToggleEpisodeMonitoring(episode) },
                            isSearching: searchingEpisodeId == episode.id,
                            isUpdating: updatingEpisodeId == episode.id
                        )
                    }
                }
                .padding(.top, AppSpacing.xs)
                .padding(.leading, AppSpacing.lg)
            }
        }
    }
}

// MARK: - Episode Card Component

struct EpisodeCard: View {
    let episode: Episode
    let onSearch: () -> Void
    let onManualSearch: () -> Void
    let onToggleMonitoring: () -> Void
    let isSearching: Bool
    let isUpdating: Bool

    private var statusColor: Color {
        switch episode.statusColor {
        case "success":
            return ColorPalette.success
        case "error":
            return ColorPalette.error
        case "info":
            return ColorPalette.info
        default:
            return ColorPalette.textMutedDark
        }
    }

    private var statusIcon: String {
        if episode.hasFile {
            return "checkmark.circle.fill"
        } else if !episode.hasAired {
            return "clock"
        } else if episode.monitored {
            return "exclamationmark.circle.fill"
        } else {
            return "eye.slash"
        }
    }

    private var formattedAirDate: String {
        guard let airDate = episode.airDateParsed else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: airDate)
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundColor(statusColor)
                .frame(width: 20)

            // Episode info
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(AppTypography.subheadline())
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    Text(episode.statusDisplay)
                        .font(AppTypography.caption2())
                        .foregroundColor(statusColor)

                    if !formattedAirDate.isEmpty {
                        Text("•")
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(formattedAirDate)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                }
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                Button(action: onToggleMonitoring) {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: episode.monitored ? "eye.fill" : "eye.slash")
                            .font(.system(size: 14))
                            .foregroundColor(episode.monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                    }
                }
                .frame(width: 30, height: 30)
                .disabled(isUpdating)

                if episode.hasAired && !episode.hasFile && episode.monitored {
                    Button(action: onSearch) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(ColorPalette.primary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .disabled(isSearching)
                }

                if episode.hasAired {
                    Button(action: onManualSearch) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 14))
                                .foregroundColor(ColorPalette.secondary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .disabled(isSearching)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.surfaceDark)
        .cornerRadius(AppRadius.sm)
    }
}

#Preview {
    NavigationStack {
        TVShowDetailView(show: TVShow(
            id: 1,
            title: "Breaking Bad",
            year: 2008,
            overview: "A high school chemistry teacher turned methamphetamine manufacturer partners with a former student to secure his family's financial future after he is diagnosed with stage three lung cancer.",
            network: "AMC",
            status: "ended",
            monitored: true,
            qualityProfileId: 4,
            images: [],
            statistics: TVShowStatistics(seasonCount: 5, episodeCount: 62, episodeFileCount: 62, totalEpisodeCount: 62, sizeOnDisk: 0, percentOfEpisodes: 100)
        ))
    }
    .preferredColorScheme(.dark)
}
