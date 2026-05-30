//
//  CalendarEventCard.swift
//  Media Manager
//
//  Card component for displaying calendar events (movie releases and TV episodes).
//

import SwiftUI

// MARK: - Static DateFormatter for time display

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter
}()

struct CalendarEventCard: View {
    let event: CalendarEvent
    var isFollowed: Bool = false
    let onTap: () -> Void

    private var typeColor: Color {
        switch event.type {
        case .movieRelease:
            return ColorPalette.primary
        case .tvEpisode:
            return ColorPalette.secondary
        }
    }

    private var typeIcon: String {
        switch event.type {
        case .movieRelease:
            return "film.fill"
        case .tvEpisode:
            return "tv.fill"
        }
    }

    private var formattedTime: String {
        timeFormatter.string(from: event.date)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                // Poster
                CachedAsyncImage(url: event.posterURL, width: 50, height: 75)
                    .cornerRadius(AppRadius.xs)

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    // Title
                    Text(event.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Year
                    Text(String(event.year))
                        .font(AppTypography.caption1(.medium))
                        .foregroundColor(typeColor)

                    // Type badge
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 10))
                        Text(event.typeLabel)
                            .font(AppTypography.caption2(.medium))
                    }
                    .foregroundColor(typeColor)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 3)
                    .background(typeColor.opacity(0.15))
                    .cornerRadius(AppRadius.xs)

                    if isFollowed {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("Radar")
                                .font(AppTypography.caption2(.medium))
                        }
                        .foregroundColor(ColorPalette.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(AppSpacing.sm)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(typeColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(CalendarEventCardButtonStyle())
    }
}

struct CalendarEventCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.sm) {
            CalendarEventCard(
                event: CalendarEvent(
                    title: "The Matrix Resurrections",
                    date: Date(),
                    type: .movieRelease(releaseType: .digital),
                    source: .movie(Movie(
                        id: 1,
                        title: "The Matrix Resurrections",
                        year: 2021,
                        overview: "Return to the Matrix",
                        runtime: 148,
                        monitored: true,
                        status: "released",
                        images: []
                    )),
                    posterURL: nil,
                    year: 2021
                ),
                onTap: {}
            )

            CalendarEventCard(
                event: CalendarEvent(
                    title: "Breaking Bad",
                    date: Date(),
                    type: .tvEpisode,
                    source: .tvShow(TVShow(
                        id: 1,
                        title: "Breaking Bad",
                        year: 2008,
                        overview: "A high school chemistry teacher",
                        network: "AMC",
                        status: "ended",
                        monitored: true,
                        qualityProfileId: 1,
                        images: [],
                        statistics: nil
                    )),
                    posterURL: nil,
                    year: 2008
                ),
                onTap: {}
            )
        }
        .padding()
    }
}
