import AppIntents
import Foundation

/// Monitor option enum for App Intents
enum TVShowMonitorOption: String, AppEnum {
    case all
    case firstSeason
    case latestSeason
    case none

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Monitor Option"

    static var caseDisplayRepresentations: [TVShowMonitorOption: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All Seasons", subtitle: "Monitor all seasons and episodes"),
        .firstSeason: DisplayRepresentation(title: "First Season", subtitle: "Only monitor the first season"),
        .latestSeason: DisplayRepresentation(title: "Latest Season", subtitle: "Only monitor the most recent season"),
        .none: DisplayRepresentation(title: "None", subtitle: "Don't monitor any episodes")
    ]

    /// Convert to the app's MonitorOption
    var toMonitorOption: MonitorOption {
        switch self {
        case .all: return .all
        case .firstSeason: return .firstSeason
        case .latestSeason: return .latestSeason
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

            // Select best quality profile (prefer HD/720p/1080p combo or id 6)
            let qualityProfileId: Int
            if let hdProfile = qualityProfiles.first(where: { $0.id == 6 || $0.name.contains("720p/1080p") }) {
                qualityProfileId = hdProfile.id
            } else if let hdProfile = qualityProfiles.first(where: { $0.name.contains("HD") || $0.name.contains("1080") }) {
                qualityProfileId = hdProfile.id
            } else if let first = qualityProfiles.first {
                qualityProfileId = first.id
            } else {
                qualityProfileId = 1
            }

            // Select first root folder
            let rootFolderPath = rootFolders.first?.path ?? "/tv/"

            // Add the TV show
            let addedShow = try await SonarrService.shared.addShow(
                show: selectedShow,
                monitorOption: monitorOption.toMonitorOption,
                qualityProfileId: qualityProfileId,
                rootFolderPath: rootFolderPath,
                searchForMissingEpisodes: searchForEpisodes
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

            let qualityProfileId = qualityProfiles.first(where: { $0.id == 6 || $0.name.contains("720p/1080p") })?.id
                ?? qualityProfiles.first(where: { $0.name.contains("HD") })?.id
                ?? qualityProfiles.first?.id ?? 1
            let rootFolderPath = rootFolders.first?.path ?? "/tv/"

            let addedShow = try await SonarrService.shared.addShow(
                show: firstResult,
                monitorOption: .all,
                qualityProfileId: qualityProfileId,
                rootFolderPath: rootFolderPath,
                searchForMissingEpisodes: true
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
