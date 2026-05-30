//
//  CalendarEvent.swift
//  Media Manager
//
//  Model for calendar events representing movie releases and TV show air dates.
//

import Foundation

/// Type of calendar event
enum CalendarEventType: Hashable {
    case movieRelease(releaseType: MovieReleaseType)
    case tvEpisode

    enum MovieReleaseType: String, Hashable {
        case theatrical = "In Theaters"
        case digital = "Digital Release"
        case physical = "Physical Release"
    }
}

/// Source reference for navigation
enum CalendarEventSource: Hashable {
    case movie(Movie)
    case tvShow(TVShow)
}

/// A calendar event representing a movie release or TV show air date
struct CalendarEvent: Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: Date
    let type: CalendarEventType
    let source: CalendarEventSource
    let posterURL: URL?
    let year: Int
    let overview: String?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        type: CalendarEventType,
        source: CalendarEventSource,
        posterURL: URL?,
        year: Int,
        overview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.type = type
        self.source = source
        self.posterURL = posterURL
        self.year = year
        self.overview = overview
    }

    /// Display label for the event type
    var typeLabel: String {
        switch type {
        case .movieRelease(let releaseType):
            return releaseType.rawValue
        case .tvEpisode:
            return "New Episode"
        }
    }

    /// Whether this is a movie event
    var isMovie: Bool {
        if case .movie = source { return true }
        return false
    }

    /// Whether this is a TV show event
    var isTVShow: Bool {
        if case .tvShow = source { return true }
        return false
    }

    /// Local library identifier used for release radar following.
    var libraryItemId: Int {
        switch source {
        case .movie(let movie):
            return movie.id
        case .tvShow(let show):
            return show.id
        }
    }

    /// Relative timing label for dashboard and release radar surfaces.
    var relativeDateLabel: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: date)
        let fallback = date.formatted(date: .abbreviated, time: .omitted)

        guard let dayOffset = calendar.dateComponents([.day], from: today, to: eventDay).day else {
            return fallback
        }

        switch dayOffset {
        case ..<0:
            return "Released"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case 2...7:
            return "In \(dayOffset) days"
        default:
            return fallback
        }
    }

    /// Release radar badge label.
    var radarBadgeText: String {
        if isNowAvailable {
            return "Now"
        }

        switch type {
        case .movieRelease(let releaseType):
            switch releaseType {
            case .theatrical:
                return "Theaters"
            case .digital:
                return "Digital"
            case .physical:
                return "Physical"
            }
        case .tvEpisode:
            return "Episode"
        }
    }

    /// Whether the release is newly available today.
    var isNowAvailable: Bool {
        let calendar = Calendar.current

        switch type {
        case .movieRelease(let releaseType):
            guard releaseType == .digital || releaseType == .physical else { return false }
            return calendar.isDateInToday(date)
        case .tvEpisode:
            return false
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Calendar Event Builder

struct CalendarEventBuilder {
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

    /// Parse an ISO8601 date string to Date
    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        return iso8601FormatterSimple.date(from: dateString)
    }

    /// Build calendar events from movies
    static func eventsFromMovies(_ movies: [Movie]) -> [CalendarEvent] {
        var events: [CalendarEvent] = []

        for movie in movies where movie.monitored {
            let posterURL = movie.images.first(where: { $0.coverType == "poster" })
                .flatMap { image in
                    if let remote = image.remoteUrl, let url = URL(string: remote) {
                        return url
                    }
                    return RadarrService.shared.imageURL(for: image.url)
                }

            // In Theaters
            if let date = parseDate(movie.inCinemas) {
                events.append(CalendarEvent(
                    title: movie.title,
                    date: date,
                    type: .movieRelease(releaseType: .theatrical),
                    source: .movie(movie),
                    posterURL: posterURL,
                    year: movie.year,
                    overview: movie.overview
                ))
            }

            // Digital Release
            if let date = parseDate(movie.digitalRelease) {
                events.append(CalendarEvent(
                    title: movie.title,
                    date: date,
                    type: .movieRelease(releaseType: .digital),
                    source: .movie(movie),
                    posterURL: posterURL,
                    year: movie.year,
                    overview: movie.overview
                ))
            }

            // Physical Release
            if let date = parseDate(movie.physicalRelease) {
                events.append(CalendarEvent(
                    title: movie.title,
                    date: date,
                    type: .movieRelease(releaseType: .physical),
                    source: .movie(movie),
                    posterURL: posterURL,
                    year: movie.year,
                    overview: movie.overview
                ))
            }
        }

        return events
    }

    /// Build calendar events from TV shows
    static func eventsFromTVShows(_ shows: [TVShow]) -> [CalendarEvent] {
        var events: [CalendarEvent] = []

        for show in shows where show.monitored {
            guard let date = parseDate(show.nextAiring) else { continue }

            let posterURL = show.images.first(where: { $0.coverType == "poster" })
                .flatMap { image in
                    if let remote = image.remoteUrl, let url = URL(string: remote) {
                        return url
                    }
                    return SonarrService.shared.imageURL(for: image.url)
                }

            events.append(CalendarEvent(
                title: show.title,
                date: date,
                type: .tvEpisode,
                source: .tvShow(show),
                posterURL: posterURL,
                year: show.year,
                overview: show.overview
            ))
        }

        return events
    }

    /// Combine and sort all events
    static func allEvents(movies: [Movie], tvShows: [TVShow]) -> [CalendarEvent] {
        let movieEvents = eventsFromMovies(movies)
        let tvEvents = eventsFromTVShows(tvShows)
        return (movieEvents + tvEvents).sorted { $0.date < $1.date }
    }

    /// Get events for a specific date
    static func events(for date: Date, from allEvents: [CalendarEvent]) -> [CalendarEvent] {
        let calendar = Calendar.current
        return allEvents.filter { event in
            calendar.isDate(event.date, inSameDayAs: date)
        }
    }

    /// Get events for a specific month
    static func events(forMonth month: Date, from allEvents: [CalendarEvent]) -> [CalendarEvent] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        return allEvents.filter { event in
            event.date >= monthInterval.start && event.date < monthInterval.end
        }
    }
}
