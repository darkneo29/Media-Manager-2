import SwiftUI

struct RadarrTroubleshootingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared
    @State private var showingLogs = false
    @State private var logs: [LogEntry] = []
    @State private var isLoadingLogs = false
    @State private var logsError: String?
    @State private var showingBackups = false
    @State private var backups: [ServerBackup] = []
    @State private var isLoadingBackups = false
    @State private var backupsError: String?
    @State private var isRestoring = false
    @State private var restoreSuccess = false
    @State private var restoreError: String?

    private var isConfigured: Bool {
        configuration.isRadarrConfigured
    }

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle("Radarr")
        #if !os(tvOS)
        .navBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Settings")
                    }
                    .foregroundColor(ColorPalette.secondary)
                }
            }
        }
        .sheet(isPresented: $showingLogs) {
            LogsSheetView(
                title: "Radarr Logs",
                logs: logs,
                isLoading: isLoadingLogs,
                error: logsError,
                onRefresh: fetchLogs
            )
        }
        .sheet(isPresented: $showingBackups) {
            BackupListSheet(
                title: "Radarr Backups",
                backups: backups,
                isLoading: isLoadingBackups,
                error: backupsError,
                onRefresh: fetchBackups,
                onRestore: restoreBackup
            )
        }
        #endif
    }

    // MARK: - tvOS Content
    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            VStack(spacing: TVSizing.sectionSpacing) {
                if !isConfigured {
                    TVStatusMessage(message: "Radarr is not configured. Please configure it in Settings first.", type: .error)

                    TVActionButton(
                        title: "Back to Settings",
                        icon: "chevron.left",
                        color: ColorPalette.secondary
                    ) {
                        dismiss()
                    }
                } else {
                    TVSettingsSection(title: "Troubleshooting") {
                        HStack(spacing: TVSizing.gridSpacing) {
                            TVActionCard(
                                icon: "doc.text.magnifyingglass",
                                iconColor: ColorPalette.primary,
                                title: "View Logs",
                                subtitle: "Recent server logs"
                            ) {
                                showingLogs = true
                                fetchLogs()
                            }

                            TVActionCard(
                                icon: "arrow.counterclockwise.circle",
                                iconColor: ColorPalette.warning,
                                title: "Restore Backup",
                                subtitle: "Restore from backup"
                            ) {
                                showingBackups = true
                                fetchBackups()
                            }
                        }
                    }

                    if restoreSuccess {
                        TVStatusMessage(message: "Backup restore initiated. Radarr is restarting...", type: .success)
                    }

                    if let error = restoreError {
                        TVStatusMessage(message: error, type: .error)
                    }

                    TVActionButton(
                        title: "Back to Settings",
                        icon: "chevron.left",
                        color: ColorPalette.secondary
                    ) {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, TVSizing.contentPadding)
            .padding(.vertical, TVSizing.sectionSpacing)
        }
        .fullScreenCover(isPresented: $showingLogs) {
            TVLogsView(
                title: "Radarr Logs",
                logs: logs,
                isLoading: isLoadingLogs,
                error: logsError,
                onRefresh: fetchLogs,
                onDismiss: { showingLogs = false }
            )
        }
        .fullScreenCover(isPresented: $showingBackups) {
            TVBackupsView(
                title: "Radarr Backups",
                backups: backups,
                isLoading: isLoadingBackups,
                error: backupsError,
                onRefresh: fetchBackups,
                onRestore: restoreBackup,
                onDismiss: { showingBackups = false }
            )
        }
    }
    #endif

    // MARK: - iOS Content
    #if !os(tvOS)
    private var iOSContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !isConfigured {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.warning)
                        Text("Radarr Not Configured")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text("Please configure Radarr in Settings first.")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, AppSpacing.xl)
                } else {
                    SettingsSection(title: "Logs", footer: "View recent log entries from Radarr to help diagnose issues.") {
                        Button(action: {
                            showingLogs = true
                            fetchLogs()
                        }) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(ColorPalette.primary)
                                Text("View Logs")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(ColorPalette.textMutedDark)
                                    .font(.caption)
                            }
                            .padding()
                        }
                    }

                    SettingsSection(title: "Backup", footer: "Restore Radarr from a previous server backup.") {
                        Button(action: {
                            showingBackups = true
                            fetchBackups()
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .foregroundColor(ColorPalette.warning)
                                Text("Restore from Backup")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(ColorPalette.textMutedDark)
                                    .font(.caption)
                            }
                            .padding()
                        }
                    }

                    // Restore status message
                    if restoreSuccess {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorPalette.success)
                            Text("Backup restore initiated. Radarr is restarting...")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.success)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    if let error = restoreError {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ColorPalette.error)
                            Text(error)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.error)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
        }
    }
    #endif

    private func fetchLogs() {
        isLoadingLogs = true
        logsError = nil

        Task {
            do {
                let fetchedLogs = try await RadarrService.shared.fetchLogs(url: configuration.radarrURL, apiKey: configuration.radarrAPIKey, count: 10)
                await MainActor.run {
                    logs = fetchedLogs
                    isLoadingLogs = false
                }
            } catch {
                await MainActor.run {
                    logsError = "Failed to fetch logs: \(error.localizedDescription)"
                    isLoadingLogs = false
                }
            }
        }
    }

    private func fetchBackups() {
        isLoadingBackups = true
        backupsError = nil

        Task {
            do {
                let fetchedBackups = try await RadarrService.shared.fetchBackups(url: configuration.radarrURL, apiKey: configuration.radarrAPIKey)
                await MainActor.run {
                    backups = fetchedBackups
                    isLoadingBackups = false
                }
            } catch {
                await MainActor.run {
                    backupsError = "Failed to fetch backups: \(error.localizedDescription)"
                    isLoadingBackups = false
                }
            }
        }
    }

    private func restoreBackup(_ backup: ServerBackup) {
        isRestoring = true
        restoreSuccess = false
        restoreError = nil

        Task {
            do {
                try await RadarrService.shared.restoreBackup(url: configuration.radarrURL, apiKey: configuration.radarrAPIKey, backupId: backup.id)
                await MainActor.run {
                    isRestoring = false
                    restoreSuccess = true
                    resetRestoreStatusAfterDelay()
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = "Failed to restore backup: \(error.localizedDescription)"
                    resetRestoreStatusAfterDelay()
                }
            }
        }
    }

    private func resetRestoreStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            restoreSuccess = false
            restoreError = nil
        }
    }
}

#Preview {
    NavigationView {
        RadarrTroubleshootingView()
    }
    .preferredColorScheme(.dark)
}
