//
//  TVPosterCard.swift
//  Media Manager
//
//  Poster card component optimized for Apple TV grid layouts.
//  Uses focus-based navigation with scale effects for remote control interaction.
//

import SwiftUI

/// A poster card designed for Apple TV grid layouts with focus effects
struct TVPosterCard: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    var badgeText: String? = nil
    var isInLibrary: Bool = false
    var statusColor: Color? = nil
    let onTap: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs) {
                // Poster with optional badge or checkmark
                posterView

                // Title and subtitle
                textContent
            }
        }
        .buttonStyle(TVPosterButtonStyle())
    }

    private var posterView: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(
                url: imageURL,
                width: TVSizing.posterWidth,
                height: TVSizing.posterHeight
            )
            .cornerRadius(TVSizing.isTV ? AppRadius.lg : AppRadius.md)
            #if os(tvOS)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(
                        isFocused ? ColorPalette.primary : Color.clear,
                        lineWidth: 4
                    )
            )
            #endif

            // Status indicator
            if let statusColor = statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: TVSizing.isTV ? 16 : 10, height: TVSizing.isTV ? 16 : 10)
                    .overlay(
                        Circle()
                            .stroke(ColorPalette.cardBackgroundDark, lineWidth: TVSizing.isTV ? 3 : 2)
                    )
                    .offset(x: TVSizing.isTV ? 6 : 4, y: TVSizing.isTV ? -6 : -4)
            }

            // Library checkmark
            if isInLibrary {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: TVSizing.isTV ? 32 : 24))
                    .foregroundColor(ColorPalette.success)
                    .background(
                        Circle()
                            .fill(ColorPalette.backgroundDark)
                            .frame(
                                width: TVSizing.isTV ? 28 : 22,
                                height: TVSizing.isTV ? 28 : 22
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .padding(TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
            } else if let badge = badgeText {
                Text(badge)
                    .font(TVSizing.isTV ? AppTypography.caption1(.semibold) : AppTypography.caption2(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
                    .padding(.vertical, TVSizing.isTV ? 4 : 2)
                    .background(ColorPalette.primary.opacity(0.9))
                    .cornerRadius(AppRadius.sm)
                    .padding(TVSizing.isTV ? AppSpacing.sm : AppSpacing.xs)
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: TVSizing.isTV ? 4 : 2) {
            Text(title)
                .font(TVSizing.isTV ? AppTypography.body(.medium) : AppTypography.caption1(.medium))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .lineLimit(TVSizing.isTV ? 2 : 1)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(TVSizing.isTV ? AppTypography.subheadline() : AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
                    .lineLimit(1)
            }
        }
        .frame(width: TVSizing.posterWidth, alignment: .leading)
    }
}

/// Button style for TV poster cards with focus effects
/// Optimized for tvOS performance with reduced shadow complexity and longer animations
struct TVPosterButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            #if os(tvOS)
            .scaleEffect(isFocused ? TVSizing.focusScale : (configuration.isPressed ? 0.95 : 1.0))
            .shadow(
                color: isFocused ? ColorPalette.primary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0,
                x: 0,
                y: isFocused ? 6 : 0  // Reduced y-offset for simpler shadow
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
            #else
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            #endif
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - TV Movie Poster Card

/// A poster card specifically for movies with status indicator
struct TVMoviePosterCard: View {
    let movie: Movie
    let onTap: () -> Void

    private var posterURL: URL? {
        movie.images.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return RadarrService.shared.imageURL(for: image.url)
            }
    }

    private var statusColor: Color {
        if movie.status == "released" && movie.monitored {
            return ColorPalette.success
        } else if movie.monitored {
            return ColorPalette.primary
        } else {
            return ColorPalette.textMutedDark
        }
    }

    var body: some View {
        TVPosterCard(
            imageURL: posterURL,
            title: movie.title,
            subtitle: String(movie.year) + (movie.runtime > 0 ? " • \(movie.runtime) min" : ""),
            statusColor: statusColor,
            onTap: onTap
        )
    }
}

// MARK: - TV Show Poster Card

/// A poster card specifically for TV shows with status indicator
struct TVShowPosterCard: View {
    let show: TVShow
    let onTap: () -> Void

    private var posterURL: URL? {
        show.images.first(where: { $0.coverType == "poster" })
            .flatMap { image in
                if let remote = image.remoteUrl, let url = URL(string: remote) {
                    return url
                }
                return SonarrService.shared.imageURL(for: image.url)
            }
    }

    private var statusColor: Color {
        if show.status == "ended" && show.monitored {
            return ColorPalette.success
        } else if show.status == "continuing" && show.monitored {
            return ColorPalette.primary
        } else if show.monitored {
            return ColorPalette.primary
        } else {
            return ColorPalette.textMutedDark
        }
    }

    var body: some View {
        TVPosterCard(
            imageURL: posterURL,
            title: show.title,
            subtitle: "\(String(show.year)) • \(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")",
            statusColor: statusColor,
            onTap: onTap
        )
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        HStack(spacing: AppSpacing.lg) {
            TVPosterCard(
                imageURL: nil,
                title: "The Matrix",
                subtitle: "1999 • 136 min",
                statusColor: ColorPalette.success,
                onTap: {}
            )

            TVPosterCard(
                imageURL: nil,
                title: "Breaking Bad",
                subtitle: "2008 • 5 Seasons",
                isInLibrary: true,
                onTap: {}
            )

            TVPosterCard(
                imageURL: nil,
                title: "Trending Movie",
                subtitle: "2024",
                badgeText: "Movie",
                onTap: {}
            )
        }
        .padding()
    }
}
