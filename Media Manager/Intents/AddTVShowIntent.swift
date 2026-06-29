import AppIntents
import Foundation

/// Monitor option enum for App Intents
enum TVShowMonitorOption: String, AppEnum {
    case all
    case future
    case missing
    case existing
    case firstSeason
    case lastSeason
    case pilot
    case recent
    case monitorSpecials
    case unmonitorSpecials
    case none

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Monitor Option"

    static var caseDisplayRepresentations: [TVShowMonitorOption: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All Seasons", subtitle: "Monitor all seasons and episodes"),
        .future: DisplayRepresentation(title: "Future Episodes", subtitle: "Only monitor episodes that have not aired yet"),
        .missing: DisplayRepresentation(title: "Missing Episodes", subtitle: "Monitor episodes that are missing files"),
        .existing: DisplayRepresentation(title: "Existing Episodes", subtitle: "Monitor episodes that already have files"),
        .firstSeason: DisplayRepresentation(title: "First Season", subtitle: "Only monitor the first season"),
        .lastSeason: DisplayRepresentation(title: "Latest Season", subtitle: "Only monitor the most recent season"),
        .pilot: DisplayRepresentation(title: "Pilot Only", subtitle: "Only monitor the pilot episode"),
        .recent: DisplayRepresentation(title: "Recent Episodes", subtitle: "Monitor recently aired episodes"),
        .monitorSpecials: DisplayRepresentation(title: "Monitor Specials", subtitle: "Monitor specials too"),
        .unmonitorSpecials: DisplayRepresentation(title: "Skip Specials", subtitle: "Leave specials unmonitored"),
        .none: DisplayRepresentation(title: "None", subtitle: "Don't monitor any episodes")
    ]

    /// Convert to the app's MonitorOption
    var toMonitorOption: MonitorOption {
        switch self {
        case .all: return .all
        case .future: return .future
        case .missing: return .missing
        case .existing: return .existing
        case .firstSeason: return .firstSeason
        case .lastSeason: return .lastSeason
        case .pilot: return .pilot
        case .recent: return .recent
        case .monitorSpecials: return .monitorSpecials
        case .unmonitorSpecials: return .unmonitorSpecials
        case .none: return .none
        }
    }
}

/// Intent to search for and add a TV show to Sonarr
struct AddTVShowIntent: AppIntent {
    static var title: LocalizedStringResource = "Add TV Show to Sonarr"
    static var description = IntentDescription("Searches for a TV show and adds it to your Sonarr library.")

    static var openAppWhenRun: Bool = false

    /// The TV show title to search for
    @Parameter(title: "TV Show Title", description: "The name of the TV show to search for")
    var searchTerm: String

    /// Monitor option
    @Parameter(title: "Monitor", description: "Which seasons to monitor", default: .all)
    var monitorOption: TVShowMonitorOption

    /// Whether to start searching for episodes after adding
    @Parameter(title: "Search for Episodes", description: "Start searching for episodes after adding", default: true)
    var searchForEpisodes: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isSonarrConfigured else {
            return .result(
                value: "Sonarr is not configured",
                dialog: "Sonarr is not configured. Please set up Sonarr in the app settings."
            )
        }

        // Validate search term
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            return .result(
                value: "No TV show title provided",
                dialog: "Please provide a TV show title to search for."
            )
        }

        do {
            // Search for TV shows
            let searchResults = try await SonarrService.shared.searchShows(term: trimmedTerm)

            guard !searchResults.isEmpty else {
                return .result(
                    value: "No TV shows found for '\(trimmedTerm)'",
                    dialog: "No TV shows found matching '\(trimmedTerm)'. Try a different search term."
                )
            }

            // If multiple results, let user choose via string disambiguation
            let selectedShow: TVShowLookup
            if searchResults.count == 1 {
                selectedShow = searchResults[0]
            } else {
                // Create string options for disambiguation
                let options = searchResults.prefix(10).map { show -> String in
                    var option = "\(show.title) (\(show.year))"
                    if show.seasonCount > 0 {
                        option += " - \(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")"
                    }
                    return option
                }
                let selectedOption = try await $searchTerm.requestDisambiguation(
                    among: Array(options),
                    dialog: IntentDialog("Multiple TV shows found. Which one did you mean?")
                )

                // Find the matching TVShowLookup
                guard let match = searchResults.prefix(10).enumerated().first(where: { index, _ in
                    options[index] == selectedOption
                })?.element else {
                    return .result(
                        value: "Could not find selected TV show",
                        dialog: "Failed to find the selected TV show. Please try again."
                    )
                }
                selectedShow = match
            }

            // Get quality profiles and root folders for defaults
            let qualityProfiles = try await SonarrService.shared.fetchQualityProfiles()
            let rootFolders = try await SonarrService.shared.fetchRootFolders()
            let tags = (try? await SonarrService.shared.fetchTags()) ?? []
            var preferences = AddMediaPreferences.shared.sonarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )
            preferences.monitorOption = monitorOption.toMonitorOption
            preferences.searchForMissingEpisodes = searchForEpisodes
            AddMediaPreferences.shared.saveSonarr(preferences)

            // Add the TV show
            let addedShow = try await SonarrService.shared.addShow(
                show: selectedShow,
                monitorOption: preferences.monitorOption,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                monitored: preferences.monitored,
                monitorNewItems: preferences.monitorNewItems,
                seriesType: preferences.seriesType,
                seasonFolder: preferences.seasonFolder,
                searchForMissingEpisodes: preferences.searchForMissingEpisodes,
                searchForCutoffUnmetEpisodes: preferences.searchForCutoffUnmetEpisodes,
                tagIds: preferences.tagIds
            )

            let searchStatus = searchForEpisodes ? " and started searching for episodes" : ""
            let monitorStatus = monitorOption == .all ? "" : " (monitoring \(monitorOption.rawValue))"
            return .result(
                value: "Added \(addedShow.title) (\(addedShow.year))",
                dialog: IntentDialog(stringLiteral: "Added '\(addedShow.title)' (\(addedShow.year)) to Sonarr\(monitorStatus)\(searchStatus).")
            )

        } catch {
            // Check if it's an "already exists" error
            let errorMessage = error.localizedDescription
            if errorMessage.contains("already") || errorMessage.contains("exists") {
                return .result(
                    value: "TV show already in library",
                    dialog: "This TV show is already in your Sonarr library."
                )
            }

            return .result(
                value: "Failed to add TV show",
                dialog: "Failed to add TV show: \(errorMessage)"
            )
        }
    }
}

/// Simpler quick-add intent that adds the first match without disambiguation
struct QuickAddTVShowIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add TV Show"
    static var description = IntentDescription("Quickly adds the best matching TV show to Sonarr without confirmation.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "TV Show Title")
    var searchTerm: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isSonarrConfigured else {
            return .result(
                value: "Sonarr is not configured",
                dialog: "Sonarr is not configured. Please set up Sonarr in the app settings."
            )
        }

        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            return .result(
                value: "No TV show title provided",
                dialog: "Please provide a TV show title."
            )
        }

        do {
            let searchResults = try await SonarrService.shared.searchShows(term: trimmedTerm)

            guard let firstResult = searchResults.first else {
                return .result(
                    value: "No TV shows found",
                    dialog: "No TV shows found for '\(trimmedTerm)'."
                )
            }

            // Get defaults
            let qualityProfiles = try await SonarrService.shared.fetchQualityProfiles()
            let rootFolders = try await SonarrService.shared.fetchRootFolders()
            let tags = (try? await SonarrService.shared.fetchTags()) ?? []
            let preferences = AddMediaPreferences.shared.sonarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )

            let addedShow = try await SonarrService.shared.addShow(
                show: firstResult,
                monitorOption: preferences.monitorOption,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                monitored: preferences.monitored,
                monitorNewItems: preferences.monitorNewItems,
                seriesType: preferences.seriesType,
                seasonFolder: preferences.seasonFolder,
                searchForMissingEpisodes: preferences.searchForMissingEpisodes,
                searchForCutoffUnmetEpisodes: preferences.searchForCutoffUnmetEpisodes,
                tagIds: preferences.tagIds
            )

            return .result(
                value: "Added \(addedShow.title)",
                dialog: IntentDialog(stringLiteral: "Added '\(addedShow.title)' (\(addedShow.year)) to Sonarr.")
            )

        } catch {
            let errorMessage = error.localizedDescription
            if errorMessage.contains("already") || errorMessage.contains("exists") {
                return .result(
                    value: "TV show already exists",
                    dialog: "This TV show is already in your library."
                )
            }
            return .result(
                value: "Failed to add TV show",
                dialog: "Error: \(errorMessage)"
            )
        }
    }
}
