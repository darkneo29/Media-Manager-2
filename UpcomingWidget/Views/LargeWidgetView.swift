//
//  LargeWidgetView.swift
//  UpcomingWidget
//
//  Large widget (2x2) showing 4-6 upcoming releases in a list.
//

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: UpcomingEntry

    private var displayEvents: [WidgetEvent] {
        Array(entry.events.prefix(6))
    }

    private var movieCount: Int {
        entry.events.filter { $0.isMovie }.count
    }

    private var tvCount: Int {
        entry.events.filter { !$0.isMovie }.count
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
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Upcoming Releases")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                // Counts
                HStack(spacing: 10) {
                    if movieCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(WidgetColors.movieAccent)
                                .frame(width: 8, height: 8)
                            Text("\(movieCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if tvCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(WidgetColors.tvAccent)
                                .frame(width: 8, height: 8)
                            Text("\(tvCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Events list
            VStack(spacing: 8) {
                ForEach(displayEvents) { event in
                    Link(destination: event.deepLinkURL ?? URL(string: "mediamanager://")!) {
                        eventRow(event)
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
    }

    private func eventRow(_ event: WidgetEvent) -> some View {
        HStack(spacing: 10) {
            // Color indicator bar
            RoundedRectangle(cornerRadius: 3)
                .fill(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)
                .frame(width: 4)

            // Type icon
            Image(systemName: event.isMovie ? "film.fill" : "tv.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)
                .frame(width: 16)

            // Title
            Text(event.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Date/Countdown
            Text(event.displayText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(event.isMovie ? WidgetColors.movieAccent : WidgetColors.tvAccent)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("All caught up!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text("No releases scheduled in the next 30 days.\nYour library is up to date.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Setup Required")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Open Dragon Media Manager\nand configure Radarr or Sonarr\nto see upcoming releases.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
