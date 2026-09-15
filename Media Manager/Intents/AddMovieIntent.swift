import AppIntents
import Foundation

/// Intent to search for and add a movie to Radarr
struct AddMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Movie to Radarr"
    static var description = IntentDescription("Searches for a movie and adds it to your Radarr library.")

    static var openAppWhenRun: Bool = false

    /// The movie title to search for
    @Parameter(title: "Movie Title", requestValueDialog: "Which movie would you like to add?")
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
            let lookupResults = try await RadarrService.shared.searchMovies(term: trimmedTerm)
            let searchResults = MediaEntityResolution.exactCatalogMatches(lookupResults, term: trimmedTerm, prefix: "tmdb", id: \.tmdbId)

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
                let choices = Array(searchResults.prefix(10))
                let labels = MediaEntityResolution.choiceLabels(choices, title: \.title, year: \.year, id: \.tmdbId)
                let selection = try await $searchTerm.requestDisambiguation(
                    among: labels, dialog: "Which movie did you mean?"
                )
                guard let index = labels.firstIndex(of: selection) else { throw MediaAddSelectionError.invalidChoice }
                selectedMovie = choices[index]
            }

            // Get quality profiles and root folders for defaults
            let qualityProfiles = try await RadarrService.shared.fetchQualityProfiles()
            let rootFolders = try await RadarrService.shared.fetchRootFolders()
            guard !qualityProfiles.isEmpty, !rootFolders.isEmpty else { throw MediaAddSelectionError.missingAddOptions }
            let tags = try? await RadarrService.shared.fetchTags()
            var preferences = AddMediaPreferences.shared.radarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )
            preferences.searchForMovie = searchForMovie

            // Add the movie
            let addedMovie = try await RadarrService.shared.addMovie(
                movie: selectedMovie,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                minimumAvailability: preferences.minimumAvailability,
                monitored: preferences.monitored,
                monitorOption: preferences.monitorOption,
                searchForMovie: preferences.searchForMovie,
                tagIds: preferences.tagIds
            )
            LibraryStateManager.shared.addMovieLocally(addedMovie)

            let searchStatus = searchForMovie ? " and started searching" : ""
            return .result(
                value: "Added \(addedMovie.title) (\(addedMovie.year))",
                dialog: IntentDialog(stringLiteral: "Added '\(addedMovie.title)' (\(addedMovie.year)) to Radarr\(searchStatus).")
            )

        } catch RadarrError.movieAlreadyExists(let title) {
            return .result(
                value: "Already in library",
                dialog: IntentDialog(stringLiteral: "'\(title)' is already in your library.")
            )
        }
    }
}

/// Simpler quick-add intent that uses saved defaults and disambiguates title collisions
struct QuickAddMovieIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Movie"
    static var description = IntentDescription("Adds the selected movie to Radarr using your saved preferences; asks when titles are ambiguous.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Movie Title", requestValueDialog: "Which movie would you like to add?")
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
            let lookupResults = try await RadarrService.shared.searchMovies(term: trimmedTerm)
            let searchResults = MediaEntityResolution.exactCatalogMatches(lookupResults, term: trimmedTerm, prefix: "tmdb", id: \.tmdbId)

            guard let firstResult = searchResults.first else {
                return .result(
                    value: "No movies found",
                    dialog: "No movies found for '\(trimmedTerm)'."
                )
            }

            let selectedResult: MovieLookup
            if searchResults.count > 1 {
                let choices = Array(searchResults.prefix(10))
                let labels = MediaEntityResolution.choiceLabels(choices, title: \.title, year: \.year, id: \.tmdbId)
                let selection = try await $searchTerm.requestDisambiguation(
                    among: labels, dialog: "Which title did you mean?"
                )
                guard let index = labels.firstIndex(of: selection) else { throw MediaAddSelectionError.invalidChoice }
                selectedResult = choices[index]
            } else { selectedResult = firstResult }

            // Get defaults
            let qualityProfiles = try await RadarrService.shared.fetchQualityProfiles()
            let rootFolders = try await RadarrService.shared.fetchRootFolders()
            guard !qualityProfiles.isEmpty, !rootFolders.isEmpty else { throw MediaAddSelectionError.missingAddOptions }
            let tags = try? await RadarrService.shared.fetchTags()
            let preferences = AddMediaPreferences.shared.radarrSettings(
                profiles: qualityProfiles,
                rootFolders: rootFolders,
                tags: tags
            )

            let addedMovie = try await RadarrService.shared.addMovie(
                movie: selectedResult,
                qualityProfileId: preferences.qualityProfileId,
                rootFolderPath: preferences.rootFolderPath,
                minimumAvailability: preferences.minimumAvailability,
                monitored: preferences.monitored,
                monitorOption: preferences.monitorOption,
                searchForMovie: preferences.searchForMovie,
                tagIds: preferences.tagIds
            )
            LibraryStateManager.shared.addMovieLocally(addedMovie)

            return .result(
                value: "Added \(addedMovie.title)",
                dialog: IntentDialog(stringLiteral: "Added '\(addedMovie.title)' (\(addedMovie.year)) to Radarr.")
            )

        } catch RadarrError.movieAlreadyExists(let title) {
            return .result(
                value: "Already in library",
                dialog: IntentDialog(stringLiteral: "'\(title)' is already in your library.")
            )
        }
    }
}
