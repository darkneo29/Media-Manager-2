import AppIntents
import Foundation

/// Intent to search for and add a movie to Radarr
struct AddMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Movie to Radarr"
    static var description = IntentDescription("Searches for a movie and adds it to your Radarr library.")

    static var openAppWhenRun: Bool = false

    /// The movie title to search for
    @Parameter(title: "Movie Title", description: "The name of the movie to search for")
    var searchTerm: String

    /// Whether to start searching for the movie after adding
    @Parameter(title: "Search for Movie", description: "Start searching for the movie file after adding", default: true)
    var searchForMovie: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isRadarrConfigured else {
            return .result(
                value: "Radarr is not configured",
                dialog: "Radarr is not configured. Please set up Radarr in the app settings."
            )
        }

        // Validate search term
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            return .result(
                value: "No movie title provided",
                dialog: "Please provide a movie title to search for."
            )
        }

        do {
            // Search for movies
            let searchResults = try await RadarrService.shared.searchMovies(term: trimmedTerm)

            guard !searchResults.isEmpty else {
                return .result(
                    value: "No movies found for '\(trimmedTerm)'",
                    dialog: "No movies found matching '\(trimmedTerm)'. Try a different search term."
                )
            }

            // If multiple results, let user choose via string disambiguation
            let selectedMovie: MovieLookup
            if searchResults.count == 1 {
                selectedMovie = searchResults[0]
            } else {
                // Create string options for disambiguation
                let options = searchResults.prefix(10).map { "\($0.title) (\($0.year))" }
                let selectedOption = try await $searchTerm.requestDisambiguation(
                    among: Array(options),
                    dialog: IntentDialog("Multiple movies found. Which one did you mean?")
                )

                // Find the matching MovieLookup by parsing the selected string
                guard let match = searchResults.prefix(10).first(where: { "\($0.title) (\($0.year))" == selectedOption }) else {
                    return .result(
                        value: "Could not find selected movie",
                        dialog: "Failed to find the selected movie. Please try again."
                    )
                }
                selectedMovie = match
            }

            // Get quality profiles and root folders for defaults
            let qualityProfiles = try await RadarrService.shared.fetchQualityProfiles()
            let rootFolders = try await RadarrService.shared.fetchRootFolders()
            let tags = (try? await RadarrService.shared.fetchTags()) ?? []
            var preferences = AddMediaPreferences.shared.radarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )
            preferences.searchForMovie = searchForMovie
            AddMediaPreferences.shared.saveRadarr(preferences)

            // Add the movie
            let addedMovie = try await RadarrService.shared.addMovie(
                movie: selectedMovie,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                minimumAvailability: preferences.minimumAvailability,
                monitored: preferences.monitored,
                searchForMovie: preferences.searchForMovie,
                tagIds: preferences.tagIds
            )

            let searchStatus = searchForMovie ? " and started searching" : ""
            return .result(
                value: "Added \(addedMovie.title) (\(addedMovie.year))",
                dialog: IntentDialog(stringLiteral: "Added '\(addedMovie.title)' (\(addedMovie.year)) to Radarr\(searchStatus).")
            )

        } catch {
            // Check if it's an "already exists" error
            let errorMessage = error.localizedDescription
            if errorMessage.contains("already") || errorMessage.contains("exists") {
                return .result(
                    value: "Movie already in library",
                    dialog: "This movie is already in your Radarr library."
                )
            }

            return .result(
                value: "Failed to add movie",
                dialog: "Failed to add movie: \(errorMessage)"
            )
        }
    }
}

/// Simpler quick-add intent that adds the first match without disambiguation
struct QuickAddMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Movie"
    static var description = IntentDescription("Quickly adds the best matching movie to Radarr without confirmation.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Movie Title")
    var searchTerm: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isRadarrConfigured else {
            return .result(
                value: "Radarr is not configured",
                dialog: "Radarr is not configured. Please set up Radarr in the app settings."
            )
        }

        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            return .result(
                value: "No movie title provided",
                dialog: "Please provide a movie title."
            )
        }

        do {
            let searchResults = try await RadarrService.shared.searchMovies(term: trimmedTerm)

            guard let firstResult = searchResults.first else {
                return .result(
                    value: "No movies found",
                    dialog: "No movies found for '\(trimmedTerm)'."
                )
            }

            // Get defaults
            let qualityProfiles = try await RadarrService.shared.fetchQualityProfiles()
            let rootFolders = try await RadarrService.shared.fetchRootFolders()
            let tags = (try? await RadarrService.shared.fetchTags()) ?? []
            let preferences = AddMediaPreferences.shared.radarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )

            let addedMovie = try await RadarrService.shared.addMovie(
                movie: firstResult,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                minimumAvailability: preferences.minimumAvailability,
                monitored: preferences.monitored,
                searchForMovie: preferences.searchForMovie,
                tagIds: preferences.tagIds
            )

            return .result(
                value: "Added \(addedMovie.title)",
                dialog: IntentDialog(stringLiteral: "Added '\(addedMovie.title)' (\(addedMovie.year)) to Radarr.")
            )

        } catch {
            let errorMessage = error.localizedDescription
            if errorMessage.contains("already") || errorMessage.contains("exists") {
                return .result(
                    value: "Movie already exists",
                    dialog: "This movie is already in your library."
                )
            }
            return .result(
                value: "Failed to add movie",
                dialog: "Error: \(errorMessage)"
            )
        }
    }
}
