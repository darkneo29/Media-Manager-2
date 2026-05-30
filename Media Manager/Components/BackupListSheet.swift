//
//  BackupListSheet.swift
//  Media Manager
//
//  A sheet view for displaying and restoring server backups
//

import SwiftUI

/// A sheet view for displaying backup list and handling restore operations
struct BackupListSheet: View {
    let title: String
    let backups: [ServerBackup]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onRestore: (ServerBackup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBackup: ServerBackup?
    @State private var showingRestoreConfirmation = false

    var body: some View {
        NavigationView {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if isLoading && backups.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.primary))
                            .scaleEffect(1.2)
                        Text("Loading backups...")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                } else if let error = error, backups.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(ColorPalette.error)
                        Text("Error Loading Backups")
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
                } else if backups.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.system(size: 48))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No Backups Found")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text("No backups are available on the server.")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            ForEach(backups) { backup in
                                BackupCard(backup: backup) {
                                    selectedBackup = backup
                                    showingRestoreConfirmation = true
                                }
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
            .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedBackup = nil
                }
                Button("Restore", role: .destructive) {
                    if let backup = selectedBackup {
                        onRestore(backup)
                        dismiss()
                    }
                }
            } message: {
                if let backup = selectedBackup {
                    Text("Are you sure you want to restore the backup from \(backup.formattedDate)?\n\nThis will replace your current configuration and restart the server. This action cannot be undone.")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A card view for displaying a single backup
struct BackupCard: View {
    let backup: ServerBackup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                // Backup icon
                ZStack {
                    Circle()
                        .fill(ColorPalette.primary.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: backupIcon)
                        .font(.system(size: 20))
                        .foregroundColor(ColorPalette.primary)
                }

                // Backup info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(backup.name)
                        .font(AppTypography.body(.medium))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(1)

                    HStack(spacing: AppSpacing.sm) {
                        // Date
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(backup.formattedDate)
                        }
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)

                        // Size
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 10))
                            Text(backup.formattedSize)
                        }
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                    }

                    // Type badge
                    BackupTypeBadge(type: backup.type)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(AppSpacing.md)
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var backupIcon: String {
        switch backup.type.lowercased() {
        case "scheduled":
            return "clock.arrow.circlepath"
        case "manual":
            return "hand.tap"
        case "update":
            return "arrow.up.circle"
        default:
            return "arrow.counterclockwise.circle"
        }
    }
}

/// A badge for displaying backup type
struct BackupTypeBadge: View {
    let type: String

    var body: some View {
        Text(displayName.uppercased())
            .font(AppTypography.caption2(.semibold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2))
            .cornerRadius(AppRadius.xs)
    }

    private var displayName: String {
        switch type.lowercased() {
        case "scheduled":
            return "Scheduled"
        case "manual":
            return "Manual"
        case "update":
            return "Update"
        default:
            return type.capitalized
        }
    }

    private var badgeColor: Color {
        switch type.lowercased() {
        case "scheduled":
            return ColorPalette.info
        case "manual":
            return ColorPalette.primary
        case "update":
            return ColorPalette.warning
        default:
            return ColorPalette.textSecondaryDark
        }
    }
}

#Preview {
    BackupListSheet(
        title: "Radarr Backups",
        backups: [
            ServerBackup(
                id: 1,
                name: "nzbdrone_backup_v4.3.2.7961_2025.12.26_03.00.00.zip",
                path: "/config/Backups/scheduled/nzbdrone_backup_v4.3.2.7961_2025.12.26_03.00.00.zip",
                type: "scheduled",
                size: 45_678_901,
                time: "2025-12-26T03:00:00.000Z"
            ),
            ServerBackup(
                id: 2,
                name: "nzbdrone_backup_v4.3.2.7961_2025.12.25_manual.zip",
                path: "/config/Backups/manual/nzbdrone_backup_v4.3.2.7961_2025.12.25_manual.zip",
                type: "manual",
                size: 43_567_890,
                time: "2025-12-25T14:30:00.000Z"
            ),
            ServerBackup(
                id: 3,
                name: "nzbdrone_backup_v4.3.1.7922_2025.12.24_update.zip",
                path: "/config/Backups/update/nzbdrone_backup_v4.3.1.7922_2025.12.24_update.zip",
                type: "update",
                size: 42_345_678,
                time: "2025-12-24T10:15:00.000Z"
            )
        ],
        isLoading: false,
        error: nil,
        onRefresh: {},
        onRestore: { _ in }
    )
}
