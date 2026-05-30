import SwiftUI

/// Card component for displaying a movie file with actions
struct MovieFileCard: View {
    let file: MovieFile
    let onDelete: () -> Void
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // File name
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(file.fileName)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    // Quality and codec info
                    HStack(spacing: AppSpacing.xs) {
                        QualityPill(text: file.qualityName)

                        if let videoCodec = file.videoCodec {
                            CodecPill(text: videoCodec)
                        }

                        if let audioCodec = file.audioCodec {
                            CodecPill(text: audioCodec)
                        }

                        if let resolution = file.mediaInfo?.resolution {
                            CodecPill(text: resolution)
                        }
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ColorPalette.error)
                            .frame(width: 32, height: 32)
                            .background(ColorPalette.surfaceDark)
                            .cornerRadius(8)
                    }
                }
                .disabled(isDeleting)
            }

            // Bottom row: File info
            HStack {
                // File size
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.success)
                    Text(file.formattedSize)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Spacer()

                // Release group if available
                if let releaseGroup = file.releaseGroup, !releaseGroup.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(releaseGroup)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
            }

            FileInspectorRows(
                path: file.path ?? file.relativePath,
                runTime: file.mediaInfo?.runTime,
                audioLanguages: file.mediaInfo?.audioLanguages,
                subtitles: file.mediaInfo?.subtitles,
                dateAdded: file.dateAdded
            )
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.success.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Card component for displaying an episode file with actions
struct EpisodeFileCard: View {
    let file: EpisodeFile
    let onDelete: () -> Void
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // File name
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(file.fileName)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    // Quality and codec info
                    HStack(spacing: AppSpacing.xs) {
                        QualityPill(text: file.qualityName)

                        if let videoCodec = file.videoCodec {
                            CodecPill(text: videoCodec)
                        }

                        if let audioCodec = file.audioCodec {
                            CodecPill(text: audioCodec)
                        }

                        if let resolution = file.mediaInfo?.resolution {
                            CodecPill(text: resolution)
                        }
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ColorPalette.error)
                            .frame(width: 32, height: 32)
                            .background(ColorPalette.surfaceDark)
                            .cornerRadius(8)
                    }
                }
                .disabled(isDeleting)
            }

            // Bottom row: File info
            HStack {
                // Season info
                HStack(spacing: 4) {
                    Image(systemName: "tv")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.secondary)
                    Text("Season \(file.seasonNumber)")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Text("•")
                    .foregroundColor(ColorPalette.textMutedDark)

                // File size
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.success)
                    Text(file.formattedSize)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Spacer()

                // Release group if available
                if let releaseGroup = file.releaseGroup, !releaseGroup.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(releaseGroup)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
            }

            FileInspectorRows(
                path: file.path ?? file.relativePath,
                runTime: file.mediaInfo?.runTime,
                audioLanguages: file.mediaInfo?.audioLanguages,
                subtitles: file.mediaInfo?.subtitles,
                dateAdded: file.dateAdded
            )
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.success.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct FileInspectorRows: View {
    let path: String?
    let runTime: String?
    let audioLanguages: String?
    let subtitles: String?
    let dateAdded: String?

    private var formattedDateAdded: String? {
        guard let dateAdded else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let simple = ISO8601DateFormatter()
        simple.formatOptions = [.withInternetDateTime]

        guard let date = fractional.date(from: dateAdded) ?? simple.date(from: dateAdded) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if let path, !path.isEmpty {
                InspectorLine(icon: "folder", text: path)
            }

            HStack(spacing: AppSpacing.sm) {
                if let runTime, !runTime.isEmpty {
                    InspectorLine(icon: "clock", text: runTime)
                }
                if let formattedDateAdded {
                    InspectorLine(icon: "calendar.badge.plus", text: formattedDateAdded)
                }
            }

            if let audioLanguages, !audioLanguages.isEmpty {
                InspectorLine(icon: "speaker.wave.2", text: audioLanguages)
            }

            if let subtitles, !subtitles.isEmpty {
                InspectorLine(icon: "captions.bubble", text: subtitles)
            }
        }
        .padding(.top, AppSpacing.xs)
    }
}

private struct InspectorLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(ColorPalette.textMutedDark)
                .frame(width: 14)
            Text(text)
                .font(AppTypography.caption2())
                .foregroundColor(ColorPalette.textMutedDark)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

/// Empty state when no file is available
struct NoFileCard: View {
    let message: String
    let onSearch: () -> Void
    let isSearching: Bool

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 32))
                .foregroundColor(ColorPalette.textMutedDark)

            Text(message)
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .multilineTextAlignment(.center)

            Button(action: onSearch) {
                HStack(spacing: AppSpacing.xs) {
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isSearching ? "Searching..." : "Search for File")
                }
                .font(AppTypography.subheadline(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(ColorPalette.primary)
                .cornerRadius(AppRadius.md)
            }
            .disabled(isSearching)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Helper Pills

struct QualityPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.caption2(.medium))
            .foregroundColor(ColorPalette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ColorPalette.secondary.opacity(0.15))
            .cornerRadius(AppRadius.pill)
    }
}

struct CodecPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.caption2())
            .foregroundColor(ColorPalette.textSecondaryDark)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ColorPalette.surfaceDark)
            .cornerRadius(4)
    }
}

// MARK: - Previews

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // Movie file card preview
                MovieFileCard(
                    file: MovieFile(
                        id: 1,
                        movieId: 1,
                        relativePath: "The Matrix (1999)/The.Matrix.1999.2160p.BluRay.x265-MOVIE.mkv",
                        path: "/movies/The Matrix (1999)/The.Matrix.1999.2160p.BluRay.x265-MOVIE.mkv",
                        size: 15_728_640_000,
                        dateAdded: "2024-01-15T10:30:00Z",
                        quality: MovieFileQuality(
                            quality: MovieFileQualityInfo(id: 18, name: "Bluray-2160p", resolution: 2160)
                        ),
                        mediaInfo: MovieFileMediaInfo(
                            videoBitDepth: 10,
                            videoBitrate: nil,
                            videoCodec: "x265",
                            videoFps: 23.976,
                            resolution: "3840x2160",
                            runTime: "2:16:17",
                            scanType: "Progressive",
                            audioBitrate: nil,
                            audioChannels: 7.1,
                            audioCodec: "TrueHD Atmos",
                            audioLanguages: "English",
                            audioStreamCount: 2,
                            subtitles: "English / Spanish"
                        ),
                        releaseGroup: "MOVIE"
                    ),
                    onDelete: {},
                    isDeleting: false
                )

                // Episode file card preview
                EpisodeFileCard(
                    file: EpisodeFile(
                        id: 1,
                        seriesId: 1,
                        seasonNumber: 1,
                        relativePath: "Breaking Bad/Season 1/Breaking.Bad.S01E01.Pilot.1080p.BluRay.x264-DEMAND.mkv",
                        path: "/tv/Breaking Bad/Season 1/Breaking.Bad.S01E01.Pilot.1080p.BluRay.x264-DEMAND.mkv",
                        size: 2_147_483_648,
                        dateAdded: "2024-01-10T15:00:00Z",
                        quality: EpisodeFileQuality(
                            quality: EpisodeFileQualityInfo(id: 7, name: "Bluray-1080p", resolution: 1080)
                        ),
                        mediaInfo: EpisodeFileMediaInfo(
                            videoBitDepth: 8,
                            videoBitrate: nil,
                            videoCodec: "x264",
                            videoFps: 23.976,
                            resolution: "1920x1080",
                            runTime: "58:00",
                            scanType: "Progressive",
                            audioBitrate: nil,
                            audioChannels: 5.1,
                            audioCodec: "DTS-HD MA",
                            audioLanguages: "English",
                            audioStreamCount: 1,
                            subtitles: "English"
                        ),
                        releaseGroup: "DEMAND"
                    ),
                    onDelete: {},
                    isDeleting: false
                )

                // No file card preview
                NoFileCard(
                    message: "No file downloaded yet. The movie is being monitored and will download when available.",
                    onSearch: {},
                    isSearching: false
                )
            }
            .padding()
        }
    }
}
