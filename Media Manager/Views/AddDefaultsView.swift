import SwiftUI

struct AddDefaultsView: View {
    @ObservedObject private var configuration = ConfigurationManager.shared

    @State private var radarrProfiles: [RadarrQualityProfile] = []
    @State private var radarrFolders: [RootFolder] = []
    @State private var radarrTags: [MediaTag] = []
    @State private var radarrSettings = RadarrAddSettings(
        qualityProfileId: 1,
        rootFolderPath: "",
        minimumAvailability: .released,
        monitored: true,
        searchForMovie: true,
        tagIds: []
    )

    @State private var sonarrProfiles: [QualityProfile] = []
    @State private var sonarrFolders: [SonarrRootFolder] = []
    @State private var sonarrTags: [MediaTag] = []
    @State private var sonarrSettings = SonarrAddSettings(
        qualityProfileId: 1,
        rootFolderPath: "",
        monitorOption: .all,
        monitored: true,
        monitorNewItems: .all,
        seriesType: .standard,
        seasonFolder: true,
        searchForMissingEpisodes: true,
        searchForCutoffUnmetEpisodes: false,
        tagIds: []
    )

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading defaults…")
                        Spacer()
                    }
                }
            }

            if configuration.isRadarrConfigured {
                movieDefaultsSection
            }

            if configuration.isSonarrConfigured {
                showDefaultsSection
            }

            if !configuration.isRadarrConfigured && !configuration.isSonarrConfigured {
                ContentUnavailableView(
                    "No Media Service Configured",
                    systemImage: "server.rack",
                    description: Text("Configure Radarr or Sonarr before choosing add defaults.")
                )
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: statusMessage.hasPrefix("Saved") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(statusMessage.hasPrefix("Saved") ? ColorPalette.success : ColorPalette.warning)
                }
            }
        }
        .addDefaultsScrollStyle()
        .background(ColorPalette.backgroundDark)
        .navigationTitle("Add Defaults")
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isLoading || isSaving)
            }
        }
        .task { await load() }
    }

    private var movieDefaultsSection: some View {
        Section {
            Picker("Quality Profile", selection: $radarrSettings.qualityProfileId) {
                ForEach(radarrProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            Picker("Root Folder", selection: $radarrSettings.rootFolderPath) {
                ForEach(radarrFolders) { folder in
                    Text(folder.folderName).tag(folder.path)
                }
            }

            Picker("Minimum Availability", selection: $radarrSettings.minimumAvailability) {
                ForEach(RadarrMinimumAvailability.allCases) { availability in
                    Text(availability.displayName).tag(availability)
                }
            }

            if !radarrTags.isEmpty {
                TagDefaultsPicker(
                    tags: radarrTags,
                    selectedTagIds: Binding(
                        get: { Set(radarrSettings.tagIds) },
                        set: { radarrSettings.tagIds = $0.sorted() }
                    )
                )
            }

            Picker("Monitor", selection: $radarrSettings.monitorOption) {
                ForEach(RadarrMonitorOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            Toggle("Search on Add", isOn: $radarrSettings.searchForMovie)

            Menu("Apply Preset") {
                ForEach(AddBehaviorPreset.allCases) { preset in
                    Button(preset.title) { applyMoviePreset(preset) }
                }
            }
        } header: {
            Label("Movie Defaults", systemImage: "film.fill")
        } footer: {
            Text("These defaults are shared by the full add screen, Discover, Siri, and Apple Watch.")
        }
    }

    private var showDefaultsSection: some View {
        Section {
            Picker("Quality Profile", selection: $sonarrSettings.qualityProfileId) {
                ForEach(sonarrProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            Picker("Root Folder", selection: $sonarrSettings.rootFolderPath) {
                ForEach(sonarrFolders) { folder in
                    Text(folder.folderName).tag(folder.path)
                }
            }

            Picker("Monitor", selection: $sonarrSettings.monitorOption) {
                ForEach(MonitorOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Series Type", selection: $sonarrSettings.seriesType) {
                ForEach(SonarrSeriesType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }

            Picker("New Episodes", selection: $sonarrSettings.monitorNewItems) {
                ForEach(SonarrNewItemMonitor.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            if !sonarrTags.isEmpty {
                TagDefaultsPicker(
                    tags: sonarrTags,
                    selectedTagIds: Binding(
                        get: { Set(sonarrSettings.tagIds) },
                        set: { sonarrSettings.tagIds = $0.sorted() }
                    )
                )
            }

            Toggle("Monitored", isOn: $sonarrSettings.monitored)
            Toggle("Season Folders", isOn: $sonarrSettings.seasonFolder)
            Toggle("Search Missing on Add", isOn: $sonarrSettings.searchForMissingEpisodes)
            Toggle("Search Cutoff Unmet", isOn: $sonarrSettings.searchForCutoffUnmetEpisodes)

            Menu("Apply Preset") {
                ForEach(AddBehaviorPreset.allCases) { preset in
                    Button(preset.title) { applyShowPreset(preset) }
                }
                Button("Future Episodes") {
                    sonarrSettings.monitored = true
                    sonarrSettings.monitorOption = .future
                    sonarrSettings.searchForMissingEpisodes = false
                    sonarrSettings.searchForCutoffUnmetEpisodes = false
                }
            }
        } header: {
            Label("TV Show Defaults", systemImage: "tv.fill")
        } footer: {
            Text("The selected monitor strategy controls which existing episodes are monitored when a show is added.")
        }
    }

    private func load() async {
        isLoading = true
        statusMessage = nil

        do {
            if configuration.isRadarrConfigured {
                async let profiles = RadarrService.shared.fetchQualityProfiles()
                async let folders = RadarrService.shared.fetchRootFolders()
                async let tags: [MediaTag]? = try? await RadarrService.shared.fetchTags()
                let values = try await (profiles, folders, tags)
                radarrProfiles = values.0
                radarrFolders = values.1
                radarrTags = values.2 ?? []
                radarrSettings = AddMediaPreferences.shared.radarrSettings(
                    profiles: values.0,
                    rootFolders: values.1,
                    tags: values.2
                )
            }

            if configuration.isSonarrConfigured {
                async let profiles = SonarrService.shared.fetchQualityProfiles()
                async let folders = SonarrService.shared.fetchRootFolders()
                async let tags: [MediaTag]? = try? await SonarrService.shared.fetchTags()
                let values = try await (profiles, folders, tags)
                sonarrProfiles = values.0
                sonarrFolders = values.1
                sonarrTags = values.2 ?? []
                sonarrSettings = AddMediaPreferences.shared.sonarrSettings(
                    profiles: values.0,
                    rootFolders: values.1,
                    tags: values.2
                )
            }
        } catch {
            statusMessage = "Could not load defaults: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func save() {
        isSaving = true
        if configuration.isRadarrConfigured {
            radarrSettings.monitored = radarrSettings.monitorOption.isMonitored
            AddMediaPreferences.shared.saveRadarr(radarrSettings)
        }
        if configuration.isSonarrConfigured {
            AddMediaPreferences.shared.saveSonarr(sonarrSettings)
        }
        statusMessage = "Saved add defaults"
        isSaving = false
    }

    private func applyMoviePreset(_ preset: AddBehaviorPreset) {
        switch preset {
        case .downloadNow:
            radarrSettings.monitorOption = .movieOnly
            radarrSettings.searchForMovie = true
        case .monitorOnly:
            radarrSettings.monitorOption = .movieOnly
            radarrSettings.searchForMovie = false
        case .addOnly:
            radarrSettings.monitorOption = .none
            radarrSettings.searchForMovie = false
        }
        radarrSettings.monitored = radarrSettings.monitorOption.isMonitored
    }

    private func applyShowPreset(_ preset: AddBehaviorPreset) {
        switch preset {
        case .downloadNow:
            sonarrSettings.monitored = true
            sonarrSettings.monitorOption = .all
            sonarrSettings.searchForMissingEpisodes = true
        case .monitorOnly:
            sonarrSettings.monitored = true
            sonarrSettings.monitorOption = .all
            sonarrSettings.searchForMissingEpisodes = false
            sonarrSettings.searchForCutoffUnmetEpisodes = false
        case .addOnly:
            sonarrSettings.monitored = false
            sonarrSettings.monitorOption = .none
            sonarrSettings.searchForMissingEpisodes = false
            sonarrSettings.searchForCutoffUnmetEpisodes = false
        }
    }
}

private extension View {
    @ViewBuilder
    func addDefaultsScrollStyle() -> some View {
        #if os(tvOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }
}

private struct TagDefaultsPicker: View {
    let tags: [MediaTag]
    @Binding var selectedTagIds: Set<Int>

    var body: some View {
        Menu {
            ForEach(tags) { tag in
                Button {
                    if selectedTagIds.contains(tag.id) {
                        selectedTagIds.remove(tag.id)
                    } else {
                        selectedTagIds.insert(tag.id)
                    }
                } label: {
                    Label(tag.label, systemImage: selectedTagIds.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            HStack {
                Text("Tags")
                Spacer()
                Text(tagSummary(selectedTagIds: selectedTagIds, tags: tags))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
