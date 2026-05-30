//
//  UpcomingTimelineProvider.swift
//  UpcomingWidget
//
//  Timeline provider for the Upcoming Releases widget.
//

import WidgetKit
import SwiftUI

private enum TimelineSettings {
    static let refreshHours = 4
}

/// Entry for the widget timeline
struct UpcomingEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEvent]
    let isConfigured: Bool

    /// Sample entry for widget preview
    static var placeholder: UpcomingEntry {
        UpcomingEntry(
            date: Date(),
            events: [
                WidgetEvent(
                    id: "preview-1",
                    title: "Dune: Part Three",
                    date: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                    isMovie: true,
                    releaseType: "In Theaters",
                    posterURL: nil,
                    year: 2025,
                    mediaId: 1
                ),
                WidgetEvent(
                    id: "preview-2",
                    title: "Severance",
                    date: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                    isMovie: false,
                    releaseType: "New Episode",
                    posterURL: nil,
                    year: 2024,
                    mediaId: 2
                ),
                WidgetEvent(
                    id: "preview-3",
                    title: "The Batman 2",
                    date: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(),
                    isMovie: true,
                    releaseType: "Digital Release",
                    posterURL: nil,
                    year: 2025,
                    mediaId: 3
                )
            ],
            isConfigured: true
        )
    }
}

/// Timeline provider for Upcoming Releases widget
struct UpcomingTimelineProvider: TimelineProvider {
    typealias Entry = UpcomingEntry

    func placeholder(in context: Context) -> UpcomingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            let entry = createEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let entry = createEntry()

        // Refresh widget every 4 hours as baseline fallback.
        let refreshDate = Calendar.current.date(byAdding: .hour, value: TimelineSettings.refreshHours, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))

        completion(timeline)
    }

    /// Create an entry from stored data
    private func createEntry() -> UpcomingEntry {
        let events = WidgetEvent.loadUpcomingEvents()
        let isConfigured = WidgetEvent.isConfigured()

        return UpcomingEntry(
            date: Date(),
            events: events,
            isConfigured: isConfigured
        )
    }
}
