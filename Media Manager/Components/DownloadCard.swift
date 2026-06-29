import SwiftUI

struct DownloadCard: View {
    let download: Download
    let onPauseResume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Top row: Name and actions
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(download.name)
                        .font(AppTypography.subheadline(.semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.xs) {
                        StatusPill(status: download.status)

                        if !download.category.isEmpty {
                            Text(download.category)
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ColorPalette.surfaceDark)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: AppSpacing.xs) {
                    Button(action: onPauseResume) {
                        Image(systemName: pauseResumeIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .frame(width: 32, height: 32)
                            .background(ColorPalette.surfaceDark)
                            .cornerRadius(8)
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ColorPalette.error)
                            .frame(width: 32, height: 32)
                            .background(ColorPalette.surfaceDark)
                            .cornerRadius(8)
                    }
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorPalette.surfaceDark)
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressGradient)
                        .frame(width: geometry.size.width * CGFloat(download.progress / 100), height: 8)
                }
            }
            .frame(height: 8)

            // Bottom row: Stats
            HStack {
                // Progress percentage
                Text("\(Int(download.progress))%")
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                // Size
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.secondary)
                    Text(sizeText)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                // Divider
                Text("•")
                    .foregroundColor(ColorPalette.textMutedDark)

                // Speed (only show if actively downloading)
                if download.status == .downloading && download.speed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10))
                            .foregroundColor(ColorPalette.secondary)
                        Text(formatSpeed(download.speed))
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }

                    Text("•")
                        .foregroundColor(ColorPalette.textMutedDark)
                }

                // Time left
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.textMutedDark)
                    Text(download.timeLeft)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(statusBorderColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var pauseResumeIcon: String {
        switch download.status {
        case .paused:
            return "play.fill"
        case .downloading, .queued:
            return "pause.fill"
        default:
            return "arrow.clockwise"
        }
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [statusColor, statusColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var statusColor: Color {
        switch download.status {
        case .downloading:
            return ColorPalette.secondary
        case .paused:
            return ColorPalette.warning
        case .queued:
            return ColorPalette.textMutedDark
        case .completed:
            return ColorPalette.success
        case .failed:
            return ColorPalette.error
        case .extracting, .verifying, .repairing, .moving, .running, .quickCheck:
            return ColorPalette.primary
        case .fetching, .propagating:
            return ColorPalette.info
        }
    }

    private var statusBorderColor: Color {
        switch download.status {
        case .downloading:
            return ColorPalette.secondary
        case .paused:
            return ColorPalette.warning
        case .failed:
            return ColorPalette.error
        default:
            return ColorPalette.divider
        }
    }

    private var sizeText: String {
        let downloaded = download.size - download.sizeLeft
        return "\(formatBytes(downloaded)) / \(formatBytes(download.size))"
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        let mbPerSec = Double(bytesPerSec) / (1024 * 1024)
        if mbPerSec >= 1 {
            return String(format: "%.1f MB/s", mbPerSec)
        } else {
            let kbPerSec = Double(bytesPerSec) / 1024
            return String(format: "%.0f KB/s", kbPerSec)
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: DownloadStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(AppTypography.caption2(.medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(AppRadius.pill)
    }

    private var statusColor: Color {
        switch status {
        case .downloading:
            return ColorPalette.secondary
        case .paused:
            return ColorPalette.warning
        case .queued:
            return ColorPalette.textSecondaryDark
        case .completed:
            return ColorPalette.success
        case .failed:
            return ColorPalette.error
        case .extracting:
            return ColorPalette.primary
        case .verifying:
            return ColorPalette.info
        case .repairing:
            return ColorPalette.warning
        case .fetching, .moving, .running, .quickCheck:
            return ColorPalette.info
        case .propagating:
            return ColorPalette.textSecondaryDark
        }
    }

    private var statusText: String {
        switch status {
        case .downloading:
            return "Downloading"
        case .paused:
            return "Paused"
        case .queued:
            return "Queued"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .extracting:
            return "Extracting"
        case .verifying:
            return "Verifying"
        case .repairing:
            return "Repairing"
        case .fetching:
            return "Fetching"
        case .propagating:
            return "Propagating"
        case .moving:
            return "Moving"
        case .running:
            return "Running"
        case .quickCheck:
            return "Quick Check"
        }
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.sm) {
            DownloadCard(
                download: Download(
                    id: "1",
                    name: "The.Matrix.1999.2160p.BluRay.x265-MOVIE",
                    category: "movies",
                    status: .downloading,
                    progress: 67.5,
                    size: 15_728_640_000,
                    sizeLeft: 5_120_000_000,
                    timeLeft: "12m 45s",
                    speed: 6_710_886
                ),
                onPauseResume: {},
                onDelete: {}
            )

            DownloadCard(
                download: Download(
                    id: "2",
                    name: "Inception.2010.1080p.BluRay.x264-SCENE",
                    category: "movies",
                    status: .paused,
                    progress: 23.8,
                    size: 8_589_934_592,
                    sizeLeft: 6_543_210_000,
                    timeLeft: "Unknown",
                    speed: 0
                ),
                onPauseResume: {},
                onDelete: {}
            )

            DownloadCard(
                download: Download(
                    id: "3",
                    name: "Interstellar.2014.2160p.WEB-DL.HDR",
                    category: "movies",
                    status: .extracting,
                    progress: 100,
                    size: 20_401_094_656,
                    sizeLeft: 0,
                    timeLeft: "2m 15s",
                    speed: 0
                ),
                onPauseResume: {},
                onDelete: {}
            )
        }
        .padding()
    }
}
