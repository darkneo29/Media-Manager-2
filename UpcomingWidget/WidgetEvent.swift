//
//  WidgetEvent.swift
//  UpcomingWidget
//
//  Simplified event model for widget data sharing via App Groups.
//  This is a copy of the model from the main app for widget access.
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

// MARK: - App Group Data Access

extension WidgetEvent {
    /// App Group identifier - must match the one configured in both targets
    static let appGroupIdentifier = "group.com.example.MediaManager"

    /// UserDefaults keys for shared data
    private enum Keys {
        static let upcomingEvents = "upcomingEvents"
        static let isConfigured = "isServerConfigured"
    }

    /// Load upcoming events from shared storage
    static func loadUpcomingEvents() -> [WidgetEvent] {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = sharedDefaults.data(forKey: Keys.upcomingEvents) else {
            return []
        }

        do {
            let events = try JSONDecoder().decode([WidgetEvent].self, from: data)
            // Filter out past events
            let now = Date()
            return events.filter { $0.date >= Calendar.current.startOfDay(for: now) }
        } catch {
            return []
        }
    }

    /// Check if servers are configured
    static func isConfigured() -> Bool {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }
        return sharedDefaults.bool(forKey: Keys.isConfigured)
    }
}
