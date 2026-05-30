//
//  BookshelfMovieCard.swift
//  Media Manager
//
//  Compact bookshelf-style movie card with poster, title, year, and summary.
//

import SwiftUI

struct BookshelfMovieCard: View {
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

    private var statusBadgeType: StatusBadge.BadgeType {
        if movie.status == "released" && movie.monitored {
            return .available
        } else if movie.monitored {
            return .monitored
        } else {
            return .unmonitored
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                // Poster
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: posterURL, width: 70, height: 105)
                        .cornerRadius(AppRadius.sm)

                    // Small status indicator dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(ColorPalette.cardBackgroundDark, lineWidth: 2)
                        )
                        .offset(x: 4, y: -4)
                }

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    // Title
                    Text(movie.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Year & Runtime
                    HStack(spacing: AppSpacing.xs) {
                        Text(String(movie.year))
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(ColorPalette.secondary)

                        if movie.runtime > 0 {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text("\(movie.runtime) min")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textMutedDark)
                        }
                    }

                    // Summary
                    if let overview = movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("No description available")
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textMutedDark)
                            .italic()
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
                    .stroke(
                        LinearGradient(
                            colors: [
                                ColorPalette.primary.opacity(0.2),
                                ColorPalette.secondary.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(BookshelfCardButtonStyle())
    }

    private var statusColor: Color {
        switch statusBadgeType {
        case .available:
            return ColorPalette.success
        case .monitored:
            return ColorPalette.primary
        case .downloading:
            return ColorPalette.secondary
        case .missing:
            return ColorPalette.warning
        case .unmonitored:
            return ColorPalette.textMutedDark
        }
    }
}

struct BookshelfCardButtonStyle: ButtonStyle {
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
            BookshelfMovieCard(
                movie: Movie(
                    id: 1,
                    title: "The Matrix",
                    year: 1999,
                    overview: "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.",
                    runtime: 136,
                    monitored: true,
                    status: "released",
                    images: []
                ),
                onTap: {}
            )

            BookshelfMovieCard(
                movie: Movie(
                    id: 2,
                    title: "Inception",
                    year: 2010,
                    overview: "A thief who steals corporate secrets through the use of dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.",
                    runtime: 148,
                    monitored: true,
                    status: "announced",
                    images: []
                ),
                onTap: {}
            )

            BookshelfMovieCard(
                movie: Movie(
                    id: 3,
                    title: "Interstellar",
                    year: 2014,
                    overview: nil,
                    runtime: 169,
                    monitored: false,
                    status: "released",
                    images: []
                ),
                onTap: {}
            )
        }
        .padding()
    }
}
