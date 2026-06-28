//
//  WidgetEvent.swift
//  Media Manager
//
//  Simplified event model for widget data sharing via App Groups.
//  This model is shared between the main app and widget extension.
//

import Foundation

/// Simplified event model for widget consumption
/// Stored in App Group UserDefaults for widget access
struct WidgetEvent: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let isMovie: Bool
    let releaseType: String
    let posterURL: String?
    let year: Int
    let mediaId: Int

    /// Deep link URL for opening this item in the app
    var deepLinkURL: URL? {
        let type = isMovie ? "movie" : "tvshow"
        return URL(string: "mediamanager://\(type)/\(mediaId)")
    }

    /// Static date formatter to avoid repeated allocations
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Formatted date string for display
    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    /// Countdown string (e.g., "Today", "Tomorrow", "In 3 days")
    var countdownText: String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEventDay = calendar.startOfDay(for: date)

        guard let daysDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfEventDay).day else {
            return formattedDate
        }

        switch daysDifference {
        case ..<0:
            return "Released"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case 2...6:
            return "In \(daysDifference) days"
        default:
            return formattedDate
        }
    }

    /// Whether to show countdown or date (countdown for < 7 days)
    var displayText: String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEventDay = calendar.startOfDay(for: date)

        guard let daysDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfEventDay).day else {
            return formattedDate
        }

        if daysDifference < 7 {
            return countdownText
        } else {
            return formattedDate
        }
    }
}

// MARK: - Factory Methods

extension WidgetEvent {
    /// Create a WidgetEvent from a CalendarEvent
    static func from(calendarEvent: CalendarEvent) -> WidgetEvent? {
        let isMovie: Bool
        let mediaId: Int

        switch calendarEvent.source {
        case .movie(let movie):
            isMovie = true
            mediaId = movie.id
        case .tvShow(let show):
            isMovie = false
            mediaId = show.id
        }

        return WidgetEvent(
            id: calendarEvent.id.uuidString,
            title: calendarEvent.title,
            date: calendarEvent.date,
            isMovie: isMovie,
            releaseType: calendarEvent.typeLabel,
            posterURL: calendarEvent.posterURL?.absoluteString,
            year: calendarEvent.year,
            mediaId: mediaId
        )
    }
}
