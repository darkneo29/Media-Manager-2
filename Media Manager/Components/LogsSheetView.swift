import SwiftUI

/// A sheet view for displaying log entries from Radarr or Sonarr
struct LogsSheetView: View {
    let title: String
    let logs: [LogEntry]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if isLoading && logs.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.primary))
                            .scaleEffect(1.2)
                        Text("Loading logs...")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                } else if let error = error, logs.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(ColorPalette.error)
                        Text("Error Loading Logs")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text(error)
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                        Button("Retry") {
                            onRefresh()
                        }
                        .font(AppTypography.body(.semibold))
                        .foregroundColor(ColorPalette.primary)
                        .padding(.top, AppSpacing.sm)
                    }
                } else if logs.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No Logs Found")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text("No recent log entries are available.")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            ForEach(logs) { log in
                                LogEntryCard(log: log)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.lg)
                    }
                    .refreshable {
                        onRefresh()
                    }
                }
            }
            .navigationTitle(title)
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(ColorPalette.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(ColorPalette.primary)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A card view for displaying a single log entry
struct LogEntryCard: View {
    let log: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                // Log level badge
                LogLevelBadge(level: log.level)

                Spacer()

                // Timestamp
                Text(log.formattedTime)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            // Log message
            Text(log.message)
                .font(AppTypography.footnote())
                .foregroundColor(ColorPalette.textPrimaryDark)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // Logger name (if available)
            if let logger = log.logger {
                Text(logger)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            // Exception details (if available)
            if let exception = log.exception, !exception.isEmpty {
                Text(exception)
                    .font(AppTypography.caption2(.medium))
                    .foregroundColor(ColorPalette.error)
                    .lineLimit(3)
                    .padding(.top, AppSpacing.xxs)
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
    }
}

/// A badge view for displaying the log level
struct LogLevelBadge: View {
    let level: String

    var body: some View {
        Text(level.uppercased())
            .font(AppTypography.caption2(.semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .cornerRadius(AppRadius.xs)
    }

    private var backgroundColor: Color {
        switch level.lowercased() {
        case "error", "fatal":
            return ColorPalette.error.opacity(0.2)
        case "warn", "warning":
            return ColorPalette.warning.opacity(0.2)
        case "info":
            return ColorPalette.info.opacity(0.2)
        case "debug", "trace":
            return ColorPalette.textMutedDark.opacity(0.2)
        default:
            return ColorPalette.info.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch level.lowercased() {
        case "error", "fatal":
            return ColorPalette.error
        case "warn", "warning":
            return ColorPalette.warning
        case "info":
            return ColorPalette.info
        case "debug", "trace":
            return ColorPalette.textSecondaryDark
        default:
            return ColorPalette.info
        }
    }
}

#Preview {
    LogsSheetView(
        title: "Radarr Logs",
        logs: [
            LogEntry(
                id: 1,
                time: "2025-12-26T10:30:00.000Z",
                level: "Info",
                logger: "MovieService",
                message: "Searching for available movies",
                exception: nil,
                exceptionType: nil
            ),
            LogEntry(
                id: 2,
                time: "2025-12-26T10:29:00.000Z",
                level: "Error",
                logger: "DownloadService",
                message: "Failed to connect to indexer",
                exception: "Connection refused",
                exceptionType: "NetworkException"
            ),
            LogEntry(
                id: 3,
                time: "2025-12-26T10:28:00.000Z",
                level: "Warn",
                logger: "DiskService",
                message: "Low disk space warning",
                exception: nil,
                exceptionType: nil
            )
        ],
        isLoading: false,
        error: nil,
        onRefresh: {}
    )
}
