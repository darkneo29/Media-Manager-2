//
//  WidgetDataService.swift
//  Media Manager
//
//  Service for sharing upcoming release data with the widget extension via App Groups.
//

import Foundation
#if !os(tvOS)
import WidgetKit
#endif

/// Service for managing widget data in App Group shared storage
class WidgetDataService {
    static let shared = WidgetDataService()

    /// App Group identifier - must match the one configured in both targets
    static let appGroupIdentifier = "group.com.example.MediaManager"
    static let reloadThrottleInterval: TimeInterval = 10 * 60
    static let timelineHours: Int = 4
    private static let widgetKind = "UpcomingWidget"

    /// UserDefaults keys for shared data
    private enum Keys {
        static let upcomingEvents = "upcomingEvents"
        static let lastUpdated = "upcomingEventsLastUpdated"
        static let isConfigured = "isServerConfigured"
    }

    private var lastReloadDate: Date?

    /// Shared UserDefaults for App Group
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupIdentifier)
    }

    private init() {}

    // MARK: - Public Methods

    /// Save upcoming events to shared storage for widget access
    /// - Parameters:
    ///   - movies: Array of movies from library
    ///   - tvShows: Array of TV shows from library
    func saveUpcomingEvents(movies: [Movie], tvShows: [TVShow]) {
        updateWidgetData(
            movies: movies,
            tvShows: tvShows,
            isConfigured: Self.isConfigured()
        )
    }

    /// Consolidated widget update entrypoint used by app views.
    /// - Parameters:
    ///   - movies: Array of movies from library
    ///   - tvShows: Array of TV shows from library
    ///   - isConfigured: Whether at least one media service is configured
    ///   - forceReload: If true, bypasses reload throttling
    func updateWidgetData(
        movies: [Movie],
        tvShows: [TVShow],
        isConfigured: Bool,
        forceReload: Bool = false
    ) {
        let events = buildUpcomingEvents(movies: movies, tvShows: tvShows)
        let payloadChanged = saveEventsIfChanged(events)
        let configChanged = saveConfigurationStatusIfChanged(isConfigured: isConfigured)

        if forceReload {
            attemptReload(reason: "forced", force: true)
            return
        }

        if payloadChanged {
            attemptReload(reason: "changed_payload")
        } else if configChanged {
            attemptReload(reason: "changed_config")
        } else {
            #if DEBUG
            print("Widget reload skipped: no meaningful changes")
            #endif
        }
    }

    /// Save configuration status (whether servers are configured)
    func saveConfigurationStatus(isConfigured: Bool) {
        if saveConfigurationStatusIfChanged(isConfigured: isConfigured) {
            attemptReload(reason: "changed_config")
        }
    }

    /// Clear all widget data
    func clearWidgetData() {
        sharedDefaults?.removeObject(forKey: Keys.upcomingEvents)
        sharedDefaults?.removeObject(forKey: Keys.lastUpdated)
        sharedDefaults?.removeObject(forKey: Keys.isConfigured)
        attemptReload(reason: "forced", force: true)
    }

    // MARK: - Reading (for Widget)

    /// Load upcoming events from shared storage
    /// Called by the widget's TimelineProvider
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
            #if DEBUG
            print("Failed to decode widget events: \(error)")
            #endif
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

    /// Get last update date
    static func lastUpdated() -> Date? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return sharedDefaults.object(forKey: Keys.lastUpdated) as? Date
    }

    // MARK: - Private Methods

    private func buildUpcomingEvents(movies: [Movie], tvShows: [TVShow]) -> [WidgetEvent] {
        // Build calendar events using existing infrastructure
        let allEvents = CalendarEventBuilder.allEvents(movies: movies, tvShows: tvShows)
        let enabledFilters = ReleaseRadarService.persistedEnabledFilters()
        let followedMovieIds = ReleaseRadarService.persistedFollowedMovieIds()
        let followedShowIds = ReleaseRadarService.persistedFollowedShowIds()

        // Filter to release-radar-enabled events from today through the next 30 days.
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: startOfToday) ?? startOfToday

        let upcomingEvents = allEvents.filter { event in
            enabledFilters.contains(ReleaseRadarService.eventFilter(for: event)) &&
            event.date >= startOfToday &&
            event.date <= thirtyDaysFromNow
        }

        // Prioritize followed titles first, then show today's newly available items ahead of the rest.
        let sortedEvents = upcomingEvents
            .sorted { lhs, rhs in
                let lhsFollowed = isFollowed(
                    event: lhs,
                    followedMovieIds: followedMovieIds,
                    followedShowIds: followedShowIds
                )
                let rhsFollowed = isFollowed(
                    event: rhs,
                    followedMovieIds: followedMovieIds,
                    followedShowIds: followedShowIds
                )

                if lhsFollowed != rhsFollowed {
                    return lhsFollowed
                }

                if lhs.isNowAvailable != rhs.isNowAvailable {
                    return lhs.isNowAvailable
                }

                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }

                return lhs.title < rhs.title
            }
            .compactMap { WidgetEvent.from(calendarEvent: $0) }

        return Array(sortedEvents.prefix(20))
    }

    private func isFollowed(
        event: CalendarEvent,
        followedMovieIds: Set<Int>,
        followedShowIds: Set<Int>
    ) -> Bool {
        switch event.source {
        case .movie(let movie):
            return followedMovieIds.contains(movie.id)
        case .tvShow(let show):
            return followedShowIds.contains(show.id)
        }
    }

    private func saveEventsIfChanged(_ events: [WidgetEvent]) -> Bool {
        guard let sharedDefaults = sharedDefaults else {
            #if DEBUG
            print("Failed to access shared UserDefaults for App Group")
            #endif
            return false
        }

        do {
            let newData = try JSONEncoder().encode(events)
            let existingData = sharedDefaults.data(forKey: Keys.upcomingEvents)

            guard existingData != newData else {
                #if DEBUG
                print("Widget payload unchanged: skipping write")
                #endif
                return false
            }

            let now = Date()
            sharedDefaults.set(newData, forKey: Keys.upcomingEvents)
            sharedDefaults.set(now, forKey: Keys.lastUpdated)
            #if DEBUG
            print("Saved \(events.count) events to widget storage at \(now.formatted(date: .abbreviated, time: .standard))")
            #endif
            return true
        } catch {
            #if DEBUG
            print("Failed to encode widget events: \(error)")
            #endif
            return false
        }
    }

    private func saveConfigurationStatusIfChanged(isConfigured: Bool) -> Bool {
        guard let sharedDefaults = sharedDefaults else {
            #if DEBUG
            print("Failed to access shared UserDefaults for App Group")
            #endif
            return false
        }

        let currentValue = sharedDefaults.object(forKey: Keys.isConfigured) as? Bool
        guard currentValue != isConfigured else {
            #if DEBUG
            print("Widget config unchanged: skipping write")
            #endif
            return false
        }

        sharedDefaults.set(isConfigured, forKey: Keys.isConfigured)
        #if DEBUG
        print("Saved widget config status: \(isConfigured)")
        #endif
        return true
    }

    private func attemptReload(reason: String, force: Bool = false) {
        #if !os(tvOS)
        let now = Date()

        if !force,
           let lastReloadDate,
           now.timeIntervalSince(lastReloadDate) < Self.reloadThrottleInterval {
            #if DEBUG
            print("Widget reload attempt: throttled (requested=\(reason))")
            #endif
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        self.lastReloadDate = now
        #if DEBUG
        print("Widget reload attempt: \(reason)")
        #endif
        #endif
    }
}
