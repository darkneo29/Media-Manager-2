//
//  MediumWidgetView.swift
//  UpcomingWidget
//
//  Medium widget (2x1) showing 2-3 upcoming releases.
//

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: UpcomingEntry

    private var displayEvents: [WidgetEvent] {
        Array(entry.events.prefix(2))  // Only 2 for better readability
    }

    var body: some View {
        if !entry.isConfigured {
            notConfiguredView
        } else if displayEvents.isEmpty {
            emptyView
        } else {
            eventsView
        }
    }

    // MARK: - Events View

    private var eventsView: some View {
        HStack(spacing: 12) {
            ForEach(displayEvents) { event in
                Link(destination: event.deepLinkURL ?? URL(string: "mediamanager://")!) {
                    eventCard(event)
                }
            }

            // Fill remaining space if only 1 event
            if displayEvents.count < 2 {
                Spacer()
            }
        }
        .padding(12)
    }

    private func eventCard(_ event: WidgetEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type indicator - compact
            HStack(spacing: 4) {
                Image(systemName: event.isMovie ? "film.fill" : "tv.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(event.isMovie ? "Movie" : "TV")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)

            Spacer()

            // Title - larger, more lines
            Text(event.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Date/Countdown - prominent
            Text(event.displayText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyView: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text("All caught up!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text("No releases in the next 30 days")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        HStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Setup Required")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Open Dragon Media Manager to configure")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}
