import SwiftUI

struct EditTVShowView: View {
    let show: TVShow
    @Environment(\.dismiss) var dismiss

    @State private var monitored: Bool
    @State private var selectedQualityProfileId: Int
    @State private var seriesType: SonarrSeriesType
    @State private var monitorNewItems: SonarrNewItemMonitor
    @State private var seasonFolder: Bool
    @State private var selectedTagIds: Set<Int>
    @State private var selectedRootFolderPath: String
    @State private var moveFiles = true
    @State private var qualityProfiles: [QualityProfile] = []
    @State private var rootFolders: [SonarrRootFolder] = []
    @State private var tags: [MediaTag] = []
    @State private var isLoadingOptions = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(show: TVShow) {
        self.show = show
        _monitored = State(initialValue: show.monitored)
        _selectedQualityProfileId = State(initialValue: show.qualityProfileId)
        _seriesType = State(initialValue: SonarrSeriesType(rawValue: show.seriesType ?? "") ?? .standard)
        _monitorNewItems = State(initialValue: SonarrNewItemMonitor(rawValue: show.monitorNewItems ?? "") ?? .all)
        _seasonFolder = State(initialValue: show.seasonFolder ?? true)
        _selectedTagIds = State(initialValue: Set(show.tags ?? []))
        _selectedRootFolderPath = State(initialValue: MediaFolderPath.currentRoot(rootFolderPath: show.rootFolderPath, path: show.path))
    }

    private var originalRootFolderPath: String {
        MediaFolderPath.currentRoot(rootFolderPath: show.rootFolderPath, path: show.path)
    }

    private var selectedTagSummary: String {
        tagSummary(selectedTagIds: selectedTagIds, tags: tags)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Show info header
                        VStack(spacing: AppSpacing.sm) {
                            Text(show.title)
                                .font(AppTypography.title3())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.center)

                            HStack(spacing: AppSpacing.xs) {
                                Text(String(show.year))
                                    .font(AppTypography.subheadline())
                                    .foregroundColor(ColorPalette.secondary)

                                if let network = show.network, !network.isEmpty {
                                    Text("•")
                                        .foregroundColor(ColorPalette.textMutedDark)
                                    Text(network)
                                        .font(AppTypography.subheadline())
                                        .foregroundColor(ColorPalette.textMutedDark)
                                }
                            }
                        }
                        .padding(.top, AppSpacing.lg)

                        // Quality Profile section
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("QUALITY".uppercased())
                                .font(AppTypography.caption1(.semibold))
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Label {
                                    Text("Quality Profile")
                                        .font(AppTypography.body())
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                } icon: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(ColorPalette.secondary)
                                        .frame(width: 28)
                                }

                                Spacer()

                                if isLoadingOptions {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(ColorPalette.secondary)
                                } else {
                                    #if os(tvOS)
                                    TVSelectionMenu(title: "Quality Profile", selection: $selectedQualityProfileId, options: qualityProfiles.map(\.id)) { value in
                                        qualityProfiles.first { $0.id == value }?.name ?? "Choose profile"
                                    }
                                    #else
                                    Picker("Quality Profile", selection: $selectedQualityProfileId) {
                                        ForEach(qualityProfiles) { profile in
                                            Text(profile.name).tag(profile.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(ColorPalette.secondary)
                                    #endif
                                }
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            Text("The quality profile determines which releases Sonarr will download")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Text("Series Type")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)

                                Spacer()

                                #if os(tvOS)
                                TVSelectionMenu(title: "Series Type", selection: $seriesType, options: SonarrSeriesType.allCases) { value in
                                    value.displayName
                                }
                                .disabled(isLoadingOptions)
                                #else
                                Picker("Series Type", selection: $seriesType) {
                                    ForEach(SonarrSeriesType.allCases) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(ColorPalette.secondary)
                                .disabled(isLoadingOptions)
                                #endif
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            HStack {
                                Text("New Episodes")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)

                                Spacer()

                                #if os(tvOS)
                                TVSelectionMenu(title: "New Episodes", selection: $monitorNewItems, options: SonarrNewItemMonitor.allCases) { value in
                                    value.displayName
                                }
                                .disabled(isLoadingOptions)
                                #else
                                Picker("New Episodes", selection: $monitorNewItems) {
                                    ForEach(SonarrNewItemMonitor.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(ColorPalette.secondary)
                                .disabled(isLoadingOptions)
                                #endif
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            if !tags.isEmpty {
                                TagSelectionMenuRow(
                                    title: "Tags",
                                    selectedLabel: selectedTagSummary,
                                    tags: tags,
                                    selectedTagIds: $selectedTagIds
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md)
                                        .stroke(ColorPalette.divider, lineWidth: 1)
                                )
                            }

                            if !rootFolders.isEmpty {
                                HStack {
                                    Label("Root Folder", systemImage: "folder")
                                        .font(AppTypography.body())
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                    Spacer()
                                    #if os(tvOS)
                                    TVSelectionMenu(title: "Root Folder", selection: $selectedRootFolderPath, options: Array(Set(rootFolders.map(\.path) + [selectedRootFolderPath])).sorted()) { value in
                                        rootFolders.first { $0.path == value }?.folderName ?? (value.isEmpty ? "Keep current folder" : value)
                                    }
                                    #else
                                    Picker("Root Folder", selection: $selectedRootFolderPath) {
                                        if !rootFolders.contains(where: { $0.path == selectedRootFolderPath }) {
                                            Text(selectedRootFolderPath.isEmpty ? "Keep current folder" : selectedRootFolderPath)
                                                .tag(selectedRootFolderPath)
                                        }
                                        ForEach(rootFolders) { folder in
                                            Text(folder.folderName).tag(folder.path)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(ColorPalette.secondary)
                                    #endif
                                }
                                .padding(.vertical, AppSpacing.sm)
                                .padding(.horizontal, AppSpacing.md)
                                .background(ColorPalette.cardBackgroundDark)
                                .cornerRadius(AppRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md)
                                        .stroke(ColorPalette.divider, lineWidth: 1)
                                )

                                if selectedRootFolderPath != originalRootFolderPath {
                                    #if os(tvOS)
                                    HStack {
                                        Text("Move existing files").font(AppTypography.body())
                                        Spacer()
                                        TVBooleanButton(title: "Move existing files", isOn: $moveFiles)
                                    }
                                    .padding(.vertical, AppSpacing.sm)
                                    .padding(.horizontal, AppSpacing.md)
                                    .background(ColorPalette.cardBackgroundDark)
                                    .cornerRadius(AppRadius.md)
                                    #else
                                    Toggle("Move existing files", isOn: $moveFiles)
                                        .tint(ColorPalette.primary)
                                        .padding(.vertical, AppSpacing.sm)
                                        .padding(.horizontal, AppSpacing.md)
                                        .background(ColorPalette.cardBackgroundDark)
                                        .cornerRadius(AppRadius.md)
                                    #endif
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // Monitoring section
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("MONITORING".uppercased())
                                .font(AppTypography.caption1(.semibold))
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Label {
                                    Text("Monitored")
                                        .font(AppTypography.body())
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                } icon: {
                                    Image(systemName: monitored ? "eye.fill" : "eye.slash.fill")
                                        .foregroundColor(monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                        .frame(width: 28)
                                }

                                Spacer()

                                #if os(tvOS)
                                TVBooleanButton(title: "Monitored", isOn: $monitored)
                                #else
                                Toggle("", isOn: $monitored)
                                    .tint(ColorPalette.primary)
                                    .labelsHidden()
                                #endif
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            Text("When monitored, Sonarr will search for and download episodes automatically")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Label {
                                    Text("Season Folders")
                                        .font(AppTypography.body())
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                } icon: {
                                    Image(systemName: "folder")
                                        .foregroundColor(ColorPalette.secondary)
                                        .frame(width: 28)
                                }

                                Spacer()

                                #if os(tvOS)
                                TVBooleanButton(title: "Season Folder", isOn: $seasonFolder)
                                #else
                                Toggle("", isOn: $seasonFolder)
                                    .tint(ColorPalette.primary)
                                    .labelsHidden()
                                #endif
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // Error message
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(ColorPalette.error)
                                Text(error)
                                    .font(AppTypography.subheadline())
                                    .foregroundColor(ColorPalette.error)
                            }
                            .padding(AppSpacing.md)
                            .frame(maxWidth: .infinity)
                            .background(ColorPalette.error.opacity(0.1))
                            .cornerRadius(AppRadius.md)
                            .padding(.horizontal, AppSpacing.md)
                        }

                        Spacer(minLength: AppSpacing.xl)
                    }
                }
            }
            .navigationTitle("Edit Show")
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(ColorPalette.textSecondaryDark)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(ColorPalette.secondary)
                    .disabled(isSaving || isLoadingOptions)
                    .opacity(isSaving ? 0.5 : 1)
                }
            }
            .onAppear {
                loadOptions()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadOptions() {
        Task {
            do {
                async let profilesTask = SonarrService.shared.fetchQualityProfiles()
                async let foldersTask = SonarrService.shared.fetchRootFolders()
                async let tagsTask: [MediaTag]? = try? await SonarrService.shared.fetchTags()
                let (profiles, folders, fetchedTags) = try await (profilesTask, foldersTask, tagsTask)
                await MainActor.run {
                    qualityProfiles = profiles
                    rootFolders = folders
                    if let fetchedTags {
                        tags = fetchedTags
                        selectedTagIds = selectedTagIds.intersection(Set(fetchedTags.map(\.id)))
                    } else {
                        errorMessage = "Tags could not be loaded. Existing tags will be preserved."
                    }
                    isLoadingOptions = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not load editing options: \(error.localizedDescription)"
                    isLoadingOptions = false
                }
            }
        }
    }

    private func saveChanges() {
        isSaving = true
        errorMessage = nil
        let rootChanged = selectedRootFolderPath != originalRootFolderPath

        var updatedShow = show
        updatedShow.monitored = monitored
        updatedShow.qualityProfileId = selectedQualityProfileId
        updatedShow.seriesType = seriesType.rawValue
        updatedShow.monitorNewItems = monitorNewItems.rawValue
        updatedShow.seasonFolder = seasonFolder
        updatedShow.tags = selectedTagIds.sorted()
        updatedShow.rootFolderPath = rootChanged && !selectedRootFolderPath.isEmpty ? selectedRootFolderPath : nil

        Task {
            do {
                try await SonarrService.shared.updateShow(show: updatedShow, moveFiles: rootChanged && moveFiles)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    EditTVShowView(show: TVShow(
        id: 1,
        title: "Breaking Bad",
        year: 2008,
        overview: "A high school chemistry teacher turned methamphetamine manufacturer.",
        network: "AMC",
        status: "ended",
        monitored: true,
        qualityProfileId: 4,
        images: [],
        statistics: TVShowStatistics(seasonCount: 5, episodeCount: 62, episodeFileCount: 62, totalEpisodeCount: 62, sizeOnDisk: 0, percentOfEpisodes: 100)
    ))
    .preferredColorScheme(.dark)
}
