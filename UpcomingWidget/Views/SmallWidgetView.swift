//
//  SmallWidgetView.swift
//  UpcomingWidget
//
//  Small widget (1x1) showing the next upcoming release.
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: UpcomingEntry

    private var nextEvent: WidgetEvent? {
        entry.events.first
    }

    var body: some View {
        if !entry.isConfigured {
            notConfiguredView
        } else if let event = nextEvent {
            eventView(event)
        } else {
            emptyView
        }
    }

    // MARK: - Event View

    private func eventView(_ event: WidgetEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Type indicator with icon
            HStack(spacing: 5) {
                Image(systemName: event.isMovie ? "film.fill" : "tv.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(event.isMovie ? "Movie" : "TV")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)

            Spacer()

            // Title - larger
            Text(event.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Countdown - prominent with accent color
            Text(event.displayText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)
        }
        .padding(14)
        .widgetURL(event.deepLinkURL)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("All caught up!")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        VStack(spacing: 6) {
            Image(systemName: "gear")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("Open app to configure")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}
