import SwiftUI

struct HistoryCard: View {
    let download: HistoryDownload
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(statusColor)
            }

            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(download.name)
                    .font(AppTypography.subheadline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(2)

                HStack(spacing: AppSpacing.xs) {
                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(AppTypography.caption2(.medium))
                            .foregroundColor(statusColor)
                    }

                    if !download.category.isEmpty {
                        Text("•")
                            .foregroundColor(ColorPalette.textMutedDark)

                        Text(download.category)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textMutedDark)
                    }
                }

                // Details row
                HStack(spacing: AppSpacing.xs) {
                    // Size
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(formatBytes(download.size))
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }

                    // Download time
                    if download.downloadTime > 0 {
                        Text("•")
                            .foregroundColor(ColorPalette.textMutedDark)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text(formatDuration(download.downloadTime))
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                        }
                    }

                    // Completion date
                    if let completedAt = download.completedAt {
                        Text("•")
                            .foregroundColor(ColorPalette.textMutedDark)

                        Text(formatDate(completedAt))
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }

                // Failure message
                if let failMessage = download.failMessage, !failMessage.isEmpty {
                    Text(failMessage)
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.error)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch download.status {
        case .completed:
            return ColorPalette.success
        case .failed:
            return ColorPalette.error
        default:
            return ColorPalette.textSecondaryDark
        }
    }

    private var statusIcon: String {
        switch download.status {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        default:
            return "circle.fill"
        }
    }

    private var statusText: String {
        switch download.status {
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        default:
            return download.status.rawValue
        }
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.sm) {
            HistoryCard(
                download: HistoryDownload(
                    id: "1",
                    name: "The.Matrix.1999.2160p.BluRay.x265-MOVIE",
                    category: "movies",
                    status: .completed,
                    size: 15_728_640_000,
                    completedAt: Date(),
                    downloadTime: 3600,
                    failMessage: nil
                ),
                onDelete: {}
            )

            HistoryCard(
                download: HistoryDownload(
                    id: "2",
                    name: "Inception.2010.1080p.BluRay.x264-SCENE",
                    category: "movies",
                    status: .failed,
                    size: 8_589_934_592,
                    completedAt: Date().addingTimeInterval(-86400),
                    downloadTime: 1800,
                    failMessage: "CRC error: repair failed"
                ),
                onDelete: {}
            )

            HistoryCard(
                download: HistoryDownload(
                    id: "3",
                    name: "Interstellar.2014.2160p.WEB-DL.HDR",
                    category: "movies",
                    status: .completed,
                    size: 20_401_094_656,
                    completedAt: Date().addingTimeInterval(-172800),
                    downloadTime: 7200,
                    failMessage: nil
                ),
                onDelete: {}
            )
        }
        .padding()
    }
}
