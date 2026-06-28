import SwiftUI
#if !os(tvOS)
import UniformTypeIdentifiers
#endif

enum SettingsDestination: Hashable {
    case radarr
    case sonarr
    case sabnzb
    case unraid
    case tmdb
    case whatsNew
    case radarrTroubleshooting
    case sonarrTroubleshooting
    case sabnzbTroubleshooting
}

#if !os(tvOS)
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [BackupService.utType, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum BackupPassphraseMode {
    case export
    case restore
}
#endif

struct SettingsView: View {
    @State private var navigationPath = NavigationPath()
    #if !os(tvOS)
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var backupDocument: BackupDocument?
    @State private var showingPassphraseSheet = false
    @State private var backupPassphraseMode: BackupPassphraseMode?
    @State private var backupPassphrase = ""
    @State private var backupPassphraseConfirmation = ""
    @State private var pendingImportBackup: SettingsBackup?
    #endif
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var syncService = iCloudSyncService.shared

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                #if os(tvOS)
                tvOSSettingsContent
                #else
                iOSSettingsContent
                #endif
            }
            .navigationTitle("Settings")
            #if !os(tvOS)
            .navBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .radarr:
                    RadarrSettingsView()
                case .sonarr:
                    SonarrSettingsView()
                case .sabnzb:
                    SabNZBSettingsView()
                case .unraid:
                    UnraidSettingsView()
                case .tmdb:
                    TMDBSettingsView()
                case .whatsNew:
                    WhatsNewView()
                case .radarrTroubleshooting:
                    RadarrTroubleshootingView()
                case .sonarrTroubleshooting:
                    SonarrTroubleshootingView()
                case .sabnzbTroubleshooting:
                    SabNZBTroubleshootingView()
                }
            }
            #if !os(tvOS)
            .fileExporter(
                isPresented: $showingExporter,
                document: backupDocument,
                contentType: BackupService.utType,
                defaultFilename: BackupService.shared.generateFileName()
            ) { result in
                switch result {
                case .success:
                    alertTitle = "Backup Complete"
                    alertMessage = "Your settings have been saved successfully."
                    showingAlert = true
                case .failure(let error):
                    alertTitle = "Backup Failed"
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
                backupDocument = nil
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [BackupService.utType, .json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showingPassphraseSheet, onDismiss: resetPassphraseState) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("Passphrase", text: $backupPassphrase)
                                .textContentType(.password)

                            if backupPassphraseMode == .export {
                                SecureField("Confirm Passphrase", text: $backupPassphraseConfirmation)
                                    .textContentType(.password)
                            }
                        } footer: {
                            Text(passphraseFooterText)
                        }
                    }
                    .navigationTitle(passphraseTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingPassphraseSheet = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button(passphraseActionTitle) {
                                handlePassphraseSubmission()
                            }
                            .disabled(!isPassphraseSubmissionEnabled)
                        }
                    }
                }
            }
            #endif
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - tvOS Settings Layout
    #if os(tvOS)
    private var tvOSSettingsContent: some View {
        ScrollView {
            VStack(spacing: TVSizing.sectionSpacing) {
                // Server Configuration Section
                TVSettingsSection(title: "Server Configuration") {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: TVSizing.gridSpacing),
                        GridItem(.flexible(), spacing: TVSizing.gridSpacing)
                    ], spacing: TVSizing.gridSpacing) {
                        TVSettingsCard(
                            icon: "film.fill",
                            iconColor: ColorPalette.primary,
                            title: "Radarr",
                            subtitle: "Movies"
                        ) {
                            navigationPath.append(SettingsDestination.radarr)
                        }

                        TVSettingsCard(
                            icon: "tv.fill",
                            iconColor: ColorPalette.success,
                            title: "Sonarr",
                            subtitle: "TV Shows"
                        ) {
                            navigationPath.append(SettingsDestination.sonarr)
                        }

                        TVSettingsCard(
                            icon: "arrow.down.circle.fill",
                            iconColor: ColorPalette.secondary,
                            title: "SabNZB",
                            subtitle: "Downloads"
                        ) {
                            navigationPath.append(SettingsDestination.sabnzb)
                        }

                        TVSettingsCard(
                            icon: "externaldrive.fill",
                            iconColor: ColorPalette.info,
                            title: "Unraid",
                            subtitle: "Server"
                        ) {
                            navigationPath.append(SettingsDestination.unraid)
                        }

                        TVSettingsCard(
                            icon: "film.stack.fill",
                            iconColor: ColorPalette.warning,
                            title: "TMDB",
                            subtitle: "Trending Data"
                        ) {
                            navigationPath.append(SettingsDestination.tmdb)
                        }
                    }
                }

                // Troubleshooting Section
                TVSettingsSection(title: "Troubleshooting") {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: TVSizing.gridSpacing),
                        GridItem(.flexible(), spacing: TVSizing.gridSpacing)
                    ], spacing: TVSizing.gridSpacing) {
                        TVSettingsCard(
                            icon: "film.fill",
                            iconColor: ColorPalette.primary,
                            title: "Radarr",
                            subtitle: "Logs & Restore"
                        ) {
                            navigationPath.append(SettingsDestination.radarrTroubleshooting)
                        }

                        TVSettingsCard(
                            icon: "tv.fill",
                            iconColor: ColorPalette.success,
                            title: "Sonarr",
                            subtitle: "Logs & Restore"
                        ) {
                            navigationPath.append(SettingsDestination.sonarrTroubleshooting)
                        }

                        TVSettingsCard(
                            icon: "arrow.down.circle.fill",
                            iconColor: ColorPalette.secondary,
                            title: "SabNZB",
                            subtitle: "Warnings"
                        ) {
                            navigationPath.append(SettingsDestination.sabnzbTroubleshooting)
                        }
                    }
                }

                // iCloud Sync Section
                TVSettingsSection(title: "iCloud Sync") {
                    HStack(spacing: AppSpacing.lg) {
                        Image(systemName: syncService.isEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                            .font(.system(size: 32))
                            .foregroundColor(syncService.isEnabled ? ColorPalette.success : ColorPalette.textMutedDark)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("iCloud Sync")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(ColorPalette.textPrimaryDark)

                            Text(syncService.isEnabled ? "Settings synced from iCloud" : "Enable to sync settings from iPhone/iPad")
                                .font(.system(size: 22))
                                .foregroundColor(ColorPalette.textSecondaryDark)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { syncService.isEnabled },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        await syncService.enableSync()
                                    }
                                } else {
                                    syncService.disableSync()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .fill(ColorPalette.cardBackgroundDark)
                    )
                }

                // About Section
                TVSettingsSection(title: "About") {
                    HStack(spacing: TVSizing.gridSpacing) {
                        TVInfoCard(
                            icon: "info.circle.fill",
                            title: "Version",
                            value: appVersionDisplay
                        )

                        TVInfoCard(
                            icon: "sparkles",
                            title: "App",
                            value: "Dragon Media Manager"
                        )
                    }

                    TVSettingsCard(
                        icon: "sparkles.rectangle.stack.fill",
                        iconColor: ColorPalette.secondary,
                        title: "What's New",
                        subtitle: WhatsNewCatalog.latestSummary
                    ) {
                        navigationPath.append(SettingsDestination.whatsNew)
                    }
                }
            }
            .padding(.horizontal, TVSizing.contentPadding)
            .padding(.vertical, TVSizing.sectionSpacing)
        }
    }
    #endif

    // MARK: - iOS Settings Layout
    #if !os(tvOS)
    private var iOSSettingsContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Server Configuration Section
                SettingsSection(title: "Server Configuration", footer: "Configure your media server connections and API keys") {
                    Button {
                        navigationPath.append(SettingsDestination.radarr)
                    } label: {
                        SettingsRow(icon: "server.rack", iconColor: ColorPalette.primary, title: "Radarr Server")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.sonarr)
                    } label: {
                        SettingsRow(icon: "server.rack", iconColor: ColorPalette.success, title: "Sonarr Server")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.sabnzb)
                    } label: {
                        SettingsRow(icon: "server.rack", iconColor: ColorPalette.secondary, title: "SabNZB Server")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.unraid)
                    } label: {
                        SettingsRow(icon: "externaldrive.fill.badge.checkmark", iconColor: ColorPalette.info, title: "Unraid Server")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.tmdb)
                    } label: {
                        SettingsRow(icon: "film.stack", iconColor: ColorPalette.warning, title: "TMDB")
                    }
                    .buttonStyle(.plain)
                }

                // Backup & Restore Section (not available on tvOS)
                SettingsSection(title: "Backup & Restore", footer: "Export your settings to a .mediabackup file. API keys and tokens are encrypted when included.") {
                    Button(action: createBackup) {
                        SettingsRow(icon: "square.and.arrow.up", iconColor: ColorPalette.info, title: "Backup Settings")
                    }
                    .buttonStyle(.plain)
                    Button(action: { showingImporter = true }) {
                        SettingsRow(icon: "square.and.arrow.down", iconColor: ColorPalette.success, title: "Restore Settings")
                    }
                    .buttonStyle(.plain)
                }

                // iCloud Sync Section
                iCloudSyncSection

                // Troubleshooting Section
                SettingsSection(title: "Troubleshooting", footer: "View server logs, warnings, and restore from server backups") {
                    Button {
                        navigationPath.append(SettingsDestination.radarrTroubleshooting)
                    } label: {
                        SettingsRow(icon: "film.fill", iconColor: ColorPalette.primary, title: "Radarr")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.sonarrTroubleshooting)
                    } label: {
                        SettingsRow(icon: "tv.fill", iconColor: ColorPalette.success, title: "Sonarr")
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(SettingsDestination.sabnzbTroubleshooting)
                    } label: {
                        SettingsRow(icon: "arrow.down.circle.fill", iconColor: ColorPalette.secondary, title: "SabNZB")
                    }
                    .buttonStyle(.plain)
                }

                // About Section
                SettingsSection(title: "About", footer: "Dragon Media Manager - A unified interface for Radarr, Sonarr, and SabNZB") {
                    SettingsRow(icon: "info.circle", iconColor: ColorPalette.info, title: "Version", value: appVersionDisplay, showChevron: false)

                    Divider()
                        .background(ColorPalette.divider)

                    Button {
                        navigationPath.append(SettingsDestination.whatsNew)
                    } label: {
                        SettingsRow(
                            icon: "sparkles.rectangle.stack.fill",
                            iconColor: ColorPalette.secondary,
                            title: "What's New",
                            value: WhatsNewCatalog.latestSummary
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .background(ColorPalette.divider)

                    if let githubURL = URL(string: "https://github.com/darkneo29/Media-Manager-2") {
                        Link(destination: githubURL) {
                            SettingsRow(icon: "link", iconColor: ColorPalette.secondary, title: "GitHub")
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func createBackup() {
        if BackupService.shared.hasSecretsConfigured() {
            backupPassphraseMode = .export
            showingPassphraseSheet = true
            return
        }

        createBackup(passphrase: nil)
    }

    private func createBackup(passphrase: String?) {
        do {
            let backup = try BackupService.shared.createBackup(passphrase: passphrase)
            let data = try BackupService.shared.encodeBackup(backup)
            backupDocument = BackupDocument(data: data)
            showingExporter = true
        } catch {
            alertTitle = "Backup Failed"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await prepareImport(from: url)
            }
        case .failure(let error):
            alertTitle = "Restore Failed"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    @MainActor
    private func prepareImport(from url: URL) async {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw BackupError.decodingFailed
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            let backup = try BackupService.shared.decodeBackup(from: data)
            if BackupService.shared.backupRequiresPassphrase(backup) {
                pendingImportBackup = backup
                backupPassphraseMode = .restore
                showingPassphraseSheet = true
            } else {
                try restoreBackup(backup, passphrase: nil)
            }
        } catch {
            alertTitle = "Restore Failed"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func restoreBackup(_ backup: SettingsBackup, passphrase: String?) throws {
        try BackupService.shared.restoreBackup(backup, passphrase: passphrase)
        alertTitle = "Restore Complete"
        alertMessage = "Your settings have been restored successfully. The app will use the restored settings."
        showingAlert = true
    }

    private var passphraseTitle: String {
        switch backupPassphraseMode {
        case .export:
            return "Encrypt Backup"
        case .restore:
            return "Unlock Backup"
        case .none:
            return "Backup Passphrase"
        }
    }

    private var passphraseActionTitle: String {
        backupPassphraseMode == .export ? "Continue" : "Restore"
    }

    private var passphraseFooterText: String {
        switch backupPassphraseMode {
        case .export:
            return "This passphrase encrypts any stored API keys and tokens included in the backup. Keep it safe because the app cannot recover it later."
        case .restore:
            return "Enter the passphrase that was used when this backup was created."
        case .none:
            return ""
        }
    }

    private var isPassphraseSubmissionEnabled: Bool {
        let trimmedPassphrase = backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassphrase.isEmpty else { return false }

        if backupPassphraseMode == .export {
            return trimmedPassphrase == backupPassphraseConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return true
    }

    private func handlePassphraseSubmission() {
        let trimmedPassphrase = backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)

        switch backupPassphraseMode {
        case .export:
            showingPassphraseSheet = false
            createBackup(passphrase: trimmedPassphrase)
        case .restore:
            guard let backup = pendingImportBackup else {
                showingPassphraseSheet = false
                return
            }

            do {
                try restoreBackup(backup, passphrase: trimmedPassphrase)
                showingPassphraseSheet = false
            } catch {
                alertTitle = "Restore Failed"
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        case .none:
            showingPassphraseSheet = false
        }
    }

    private func resetPassphraseState() {
        backupPassphrase = ""
        backupPassphraseConfirmation = ""
        backupPassphraseMode = nil
        pendingImportBackup = nil
    }

    // MARK: - iCloud Sync Section

    private var iCloudSyncSection: some View {
        SettingsSection(
            title: "iCloud Sync",
            footer: syncService.isEnabled
                ? "Settings are synced across your Apple devices signed into the same iCloud account."
                : "Enable to sync your server settings across all your devices."
        ) {
            // Sync Toggle Row
            HStack {
                Label {
                    Text("iCloud Sync")
                        .font(AppTypography.body())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundColor(ColorPalette.info)
                        .frame(width: 28)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { syncService.isEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                await syncService.enableSync()
                            }
                        } else {
                            syncService.disableSync()
                        }
                    }
                ))
                .labelsHidden()
                .tint(ColorPalette.primary)
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .background(ColorPalette.cardBackgroundDark)

            // Sync Status Row (only shown when enabled)
            if syncService.isEnabled {
                Divider()
                    .background(ColorPalette.divider)

                HStack {
                    Label {
                        Text("Status")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                    } icon: {
                        syncStatusIcon
                            .foregroundColor(syncStatusColor)
                            .frame(width: 28)
                    }

                    Spacer()

                    Text(syncService.syncStatus.displayText)
                        .font(AppTypography.body())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }
                .padding(.vertical, AppSpacing.sm)
                .padding(.horizontal, AppSpacing.md)
                .background(ColorPalette.cardBackgroundDark)

                // Sync Now Button
                Divider()
                    .background(ColorPalette.divider)

                Button(action: { syncService.syncNow() }) {
                    HStack {
                        Label {
                            Text("Sync Now")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(ColorPalette.secondary)
                                .frame(width: 28)
                        }

                        Spacer()

                        if case .syncing = syncService.syncStatus {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.secondary))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ColorPalette.textMutedDark)
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
                    .background(ColorPalette.cardBackgroundDark)
                }
                .buttonStyle(.plain)
                .disabled(syncService.syncStatus == .syncing)
            }
        }
    }

    private var syncStatusIcon: Image {
        switch syncService.syncStatus {
        case .disabled:
            return Image(systemName: "icloud.slash")
        case .syncing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .synced:
            return Image(systemName: "checkmark.icloud")
        case .error:
            return Image(systemName: "exclamationmark.icloud")
        }
    }

    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .disabled:
            return ColorPalette.textMutedDark
        case .syncing:
            return ColorPalette.info
        case .synced:
            return ColorPalette.success
        case .error:
            return ColorPalette.error
        }
    }
    #endif
}

// MARK: - tvOS Components

#if os(tvOS)
/// Section header for tvOS settings
struct TVSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(title.uppercased())
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .tracking(2)

            content
        }
    }
}

/// Large focusable card for tvOS settings navigation
struct TVSettingsCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundColor(iconColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Text(subtitle)
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.secondary.opacity(0.4) : Color.clear,
                radius: isFocused ? 20 : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
    }
}

/// Info card for displaying static information on tvOS
struct TVInfoCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(ColorPalette.secondary)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.system(size: 22))
                    .foregroundColor(ColorPalette.textSecondaryDark)

                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(ColorPalette.cardBackgroundDark)
        )
    }
}
#endif

struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title.uppercased())
                .font(AppTypography.caption1(.semibold))
                .foregroundColor(ColorPalette.textMutedDark)
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xxs)

            VStack(spacing: 1) {
                content
            }
            .background(ColorPalette.cardBackgroundDark)
            .cornerRadius(AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(ColorPalette.divider, lineWidth: 1)
            )

            if let footer = footer {
                Text(footer)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.xxs)
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    var showChevron: Bool = true

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .font(AppTypography.body())
                    .foregroundColor(ColorPalette.textPrimaryDark)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 28)
            }

            Spacer()

            if let value = value {
                Text(value)
                    .font(AppTypography.body())
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
