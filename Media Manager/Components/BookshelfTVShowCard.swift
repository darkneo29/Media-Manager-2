import SwiftUI

struct BookshelfTVShowCard: View {
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

    private var statusBadgeType: StatusBadge.BadgeType {
        if show.status == "ended" && show.monitored {
            return .available
        } else if show.status == "continuing" && show.monitored {
            return .monitored
        } else if show.monitored {
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
                    Text(show.title)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Year, Seasons & Network
                    HStack(spacing: AppSpacing.xs) {
                        Text(String(show.year))
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(ColorPalette.secondary)

                        Text("•")
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("\(show.seasonCount) Season\(show.seasonCount != 1 ? "s" : "")")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textMutedDark)

                        if let network = show.network, !network.isEmpty {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text(network)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .lineLimit(1)
                        }
                    }

                    // Summary
                    if let overview = show.overview, !overview.isEmpty {
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

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.sm) {
            BookshelfTVShowCard(
                show: TVShow(
                    id: 1,
                    title: "Breaking Bad",
                    year: 2008,
                    overview: "A high school chemistry teacher turned methamphetamine manufacturer partners with a former student.",
                    network: "AMC",
                    status: "ended",
                    monitored: true,
                    qualityProfileId: 4,
                    images: [],
                    statistics: TVShowStatistics(seasonCount: 5, episodeCount: 62, episodeFileCount: 62, totalEpisodeCount: 62, sizeOnDisk: 0, percentOfEpisodes: 100)
                ),
                onTap: {}
            )

            BookshelfTVShowCard(
                show: TVShow(
                    id: 2,
                    title: "Stranger Things",
                    year: 2016,
                    overview: "When a young boy disappears, his mother, a police chief and his friends must confront terrifying supernatural forces.",
                    network: "Netflix",
                    status: "continuing",
                    monitored: true,
                    qualityProfileId: 4,
                    images: [],
                    statistics: TVShowStatistics(seasonCount: 4, episodeCount: 34, episodeFileCount: 34, totalEpisodeCount: 34, sizeOnDisk: 0, percentOfEpisodes: 100)
                ),
                onTap: {}
            )

            BookshelfTVShowCard(
                show: TVShow(
                    id: 3,
                    title: "The Office",
                    year: 2005,
                    overview: nil,
                    network: "NBC",
                    status: "ended",
                    monitored: false,
                    qualityProfileId: 4,
                    images: [],
                    statistics: TVShowStatistics(seasonCount: 9, episodeCount: 201, episodeFileCount: 201, totalEpisodeCount: 201, sizeOnDisk: 0, percentOfEpisodes: 100)
                ),
                onTap: {}
            )
        }
        .padding()
    }
}
