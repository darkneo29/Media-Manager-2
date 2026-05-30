import AppIntents
import Foundation

/// Intent to get upcoming movie and TV show releases
struct GetUpcomingReleasesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Upcoming Releases"
    static var description = IntentDescription("Gets a count and summary of upcoming movie and TV show releases from your library.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Days Ahead", default: 30)
    var daysAhead: Int

    // Date formatters for parsing
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterSimple: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        if let date = Self.iso8601Formatter.date(from: dateString) {
            return date
        }
        return Self.iso8601FormatterSimple.date(from: dateString)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        let radarrConfigured = config.isRadarrConfigured
        let sonarrConfigured = config.isSonarrConfigured

        guard radarrConfigured || sonarrConfigured else {
            return .result(
                value: "No services configured",
                dialog: "Neither Radarr nor Sonarr is configured. Please set up at least one service in the app settings."
            )
        }

        var upcomingMovies: [Movie] = []
        var upcomingShows: [TVShow] = []
        let effectiveDays = max(1, daysAhead)
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: effectiveDays, to: now) ?? now

        // Fetch movies if Radarr is configured
        if radarrConfigured {
            do {
                let movies = try await RadarrService.shared.fetchMovies()
                upcomingMovies = movies.filter { movie in
                    // Check for upcoming releases
                    if let digitalRelease = parseDate(movie.digitalRelease), digitalRelease > now && digitalRelease <= futureDate {
                        return true
                    }
                    if let physicalRelease = parseDate(movie.physicalRelease), physicalRelease > now && physicalRelease <= futureDate {
                        return true
                    }
                    if let inCinemas = parseDate(movie.inCinemas), inCinemas > now && inCinemas <= futureDate {
                        return true
                    }
                    return false
                }
            } catch {
                // Continue with TV shows even if movies fail
            }
        }

        // Fetch TV shows if Sonarr is configured
        if sonarrConfigured {
            do {
                let shows = try await SonarrService.shared.fetchShows()
                upcomingShows = shows.filter { show in
                    if let nextAiring = parseDate(show.nextAiring), nextAiring > now && nextAiring <= futureDate {
                        return true
                    }
                    return false
                }
            } catch {
                // Continue even if TV shows fail
            }
        }

        let totalCount = upcomingMovies.count + upcomingShows.count

        if totalCount == 0 {
            return .result(
                value: "No upcoming releases in the next \(effectiveDays) days",
                dialog: "You have no upcoming releases in the next \(effectiveDays) days."
            )
        }

        var summary = "You have \(totalCount) upcoming release\(totalCount == 1 ? "" : "s") in the next \(effectiveDays) days"

        if !upcomingMovies.isEmpty {
            summary += ": \(upcomingMovies.count) movie\(upcomingMovies.count == 1 ? "" : "s")"
        }
        if !upcomingShows.isEmpty {
            if !upcomingMovies.isEmpty {
                summary += " and"
            } else {
                summary += ":"
            }
            summary += " \(upcomingShows.count) TV episode\(upcomingShows.count == 1 ? "" : "s")"
        }

        // Add first few titles
        var titles: [String] = []
        titles.append(contentsOf: upcomingMovies.prefix(2).map { $0.title })
        titles.append(contentsOf: upcomingShows.prefix(2).map { $0.title })

        if !titles.isEmpty {
            summary += ". Including: \(titles.joined(separator: ", "))"
        }

        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: summary)
        )
    }
}
