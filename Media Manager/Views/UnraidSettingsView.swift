import SwiftUI

struct UnraidSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared

    // Local state for editing (avoids lag from @AppStorage writes on every keystroke)
    @State private var editingURL: String = ""
    @State private var editingAPIKey: String = ""
    @State private var showMediaStackFirst: Bool = true
    @State private var temperatureUnit: String = "celsius"

    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectedHostname: String?
    @State private var connectedVersion: String?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle("Unraid Settings")
        #if !os(tvOS)
        .navBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    saveSettings()
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
        #endif
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            // Cancel any pending reset task
            resetTask?.cancel()
            // Save settings on dismiss
            saveSettings()
        }
        .onChange(of: showMediaStackFirst) { _, _ in
            // Auto-save display preference changes
            saveDisplayPreferences()
        }
        .onChange(of: temperatureUnit) { _, _ in
            // Auto-save display preference changes
            saveDisplayPreferences()
        }
    }

    // MARK: - tvOS Content
    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            VStack(spacing: TVSizing.sectionSpacing) {
                // Experimental Notice
                TVStatusMessage(
                    message: "Unraid integration is experimental and highly dependent on your Unraid version. Not all features may work correctly on every setup.",
                    type: .warning
                )

                // Connection Section
                TVSettingsSection(title: "Connection") {
                    VStack(spacing: AppSpacing.lg) {
                        TVTextFieldCard(
                            label: "Server URL",
                            placeholder: "http://tower.local",
                            text: $editingURL,
                            icon: "link"
                        )

                        TVTextFieldCard(
                            label: "API Key",
                            placeholder: "Enter your API key",
                            text: $editingAPIKey,
                            icon: "key.fill",
                            isSecure: true
                        )
                    }
                }

                // Test Connection Button
                TVActionButton(
                    title: buttonText,
                    icon: connectionIcon,
                    color: buttonBackground,
                    isLoading: isTesting
                ) {
                    testConnection()
                }

                // Status Messages
                if case .success = connectionStatus, let hostname = connectedHostname {
                    TVStatusMessage(
                        message: "Connected to \(hostname)" + (connectedVersion.map { " (Unraid \($0))" } ?? ""),
                        type: .success
                    )
                }

                if case .failure(let message) = connectionStatus {
                    TVStatusMessage(message: message, type: .error)
                }

                // Display Preferences Section
                TVSettingsSection(title: "Display Preferences") {
                    VStack(spacing: AppSpacing.lg) {
                        // Media Stack First Toggle
                        TVToggleCard(
                            title: "Media Stack First",
                            subtitle: "Show Radarr, Sonarr, etc. at the top",
                            isOn: $showMediaStackFirst
                        )

                        // Temperature Unit Picker
                        TVPickerCard(
                            title: "Temperature Unit",
                            selection: $temperatureUnit,
                            options: [
                                ("celsius", "Celsius"),
                                ("fahrenheit", "Fahrenheit")
                            ]
                        )
                    }
                }

                // Requirements Section
                TVSettingsSection(title: "Requirements") {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        TVRequirementRow(
                            icon: "checkmark.circle.fill",
                            iconColor: ColorPalette.success,
                            text: "Unraid 7.2+ (built-in API)"
                        )
                        TVRequirementRow(
                            icon: "checkmark.circle.fill",
                            iconColor: ColorPalette.success,
                            text: "Or Unraid Connect plugin for 6.x"
                        )
                        TVRequirementRow(
                            icon: "key.fill",
                            iconColor: ColorPalette.warning,
                            text: "API key with 'viewer' role minimum"
                        )
                        TVRequirementRow(
                            icon: "network",
                            iconColor: ColorPalette.info,
                            text: "Same local network as Unraid server"
                        )
                    }
                    .padding(AppSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .fill(ColorPalette.cardBackgroundDark)
                    )
                }

                // Help Section
                TVSettingsSection(title: "Help") {
                    TVHelpCard(service: .unraid)
                }
            }
            .padding(.horizontal, TVSizing.contentPadding)
            .padding(.vertical, TVSizing.sectionSpacing)
        }
    }

    private var connectionIcon: String {
        switch connectionStatus {
        case .idle: return "antenna.radiowaves.left.and.right"
        case .testing: return "antenna.radiowaves.left.and.right"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }
    #endif

    // MARK: - iOS Content
    #if !os(tvOS)
    private var iOSContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Experimental Notice
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "flask.fill")
                        .foregroundColor(ColorPalette.warning)
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Experimental Feature")
                            .font(AppTypography.caption1(.semibold))
                            .foregroundColor(ColorPalette.warning)
                        Text("Unraid integration is experimental and highly dependent on your Unraid version. Not all features may work correctly on every setup.")
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ColorPalette.warning.opacity(0.1))
                .cornerRadius(AppRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(ColorPalette.warning.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, AppSpacing.md)

                // Connection Section
                SettingsSection(title: "Connection", footer: "Enter your Unraid server URL and API key.") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Server URL")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .frame(width: 100, alignment: .leading)

                            TextField("http://tower.local", text: $editingURL)
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                        }
                        .padding()

                        Divider()
                            .background(ColorPalette.divider)

                        HStack {
                            Text("API Key")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .frame(width: 100, alignment: .leading)

                            SecureField("API Key", text: $editingAPIKey)
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding()

                        Divider()
                            .background(ColorPalette.divider)

                        APIKeyHelpButton(service: .unraid)
                            .padding()
                    }
                }

                // Test Connection Button
                Button(action: testConnection) {
                    HStack(spacing: AppSpacing.xs) {
                        if case .testing = connectionStatus {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.backgroundDark))
                                .scaleEffect(0.8)
                        }
                        Text(buttonText)
                            .font(AppTypography.body(.semibold))
                    }
                    .foregroundColor(buttonTextColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonBackground)
                    .cornerRadius(AppRadius.md)
                }
                .disabled(isTesting)
                .padding(.horizontal, AppSpacing.md)

                // Connection Status Messages
                if case .success = connectionStatus, let hostname = connectedHostname {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(ColorPalette.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected to \(hostname)")
                                .font(AppTypography.caption1(.medium))
                                .foregroundColor(ColorPalette.success)
                            if let version = connectedVersion {
                                Text("Unraid \(version)")
                                    .font(AppTypography.caption2())
                                    .foregroundColor(ColorPalette.textSecondaryDark)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                if case .failure(let message) = connectionStatus {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(ColorPalette.error)
                        Text(message)
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.error)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                #if DEBUG
                // Debug: Discover Schema Button
                Button(action: discoverSchema) {
                    Text("Discover Schema (Debug)")
                        .font(AppTypography.caption1(.medium))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(ColorPalette.cardBackgroundDark)
                        .cornerRadius(AppRadius.sm)
                }
                .padding(.horizontal, AppSpacing.md)
                #endif

                // Display Preferences Section
                SettingsSection(title: "Display Preferences", footer: "Customize how your Unraid server information is displayed.") {
                    VStack(spacing: 0) {
                        // Show Media Stack First Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Media Stack First")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)
                                Text("Show Radarr, Sonarr, etc. at the top")
                                    .font(AppTypography.caption2())
                                    .foregroundColor(ColorPalette.textMutedDark)
                            }
                            Spacer()
                            Toggle("", isOn: $showMediaStackFirst)
                                .labelsHidden()
                                .tint(ColorPalette.secondary)
                        }
                        .padding()

                        Divider()
                            .background(ColorPalette.divider)

                        // Temperature Unit Picker
                        HStack {
                            Text("Temperature Unit")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                            Spacer()
                            Picker("", selection: $temperatureUnit) {
                                Text("Celsius").tag("celsius")
                                Text("Fahrenheit").tag("fahrenheit")
                            }
                            .pickerStyle(.menu)
                            .tint(ColorPalette.secondary)
                        }
                        .padding()
                    }
                }

                // Requirements Section
                SettingsSection(title: "Requirements", footer: nil) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        RequirementRow(
                            icon: "checkmark.circle.fill",
                            iconColor: ColorPalette.success,
                            text: "Unraid 7.2+ (built-in API)"
                        )
                        RequirementRow(
                            icon: "checkmark.circle.fill",
                            iconColor: ColorPalette.success,
                            text: "Or Unraid Connect plugin for 6.x"
                        )
                        RequirementRow(
                            icon: "key.fill",
                            iconColor: ColorPalette.warning,
                            text: "API key with 'viewer' role minimum"
                        )
                        RequirementRow(
                            icon: "network",
                            iconColor: ColorPalette.info,
                            text: "Same local network as Unraid server"
                        )
                    }
                    .padding()
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xl)
        }
    }
    #endif

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        editingURL = configuration.unraidURL
        editingAPIKey = configuration.unraidAPIKey
        showMediaStackFirst = defaults.object(forKey: "unraidShowMediaStackFirst") as? Bool ?? true
        temperatureUnit = defaults.string(forKey: "unraidTemperatureUnit") ?? "celsius"
    }

    private func saveSettings() {
        try? configuration.saveUnraid(url: editingURL, apiKey: editingAPIKey)
        saveDisplayPreferences()
    }

    private func saveDisplayPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(showMediaStackFirst, forKey: "unraidShowMediaStackFirst")
        defaults.set(temperatureUnit, forKey: "unraidTemperatureUnit")
    }

    // MARK: - Connection Test

    private var isTesting: Bool {
        if case .testing = connectionStatus { return true }
        return false
    }

    private var buttonText: String {
        switch connectionStatus {
        case .idle: return "Test Connection"
        case .testing: return "Testing..."
        case .success: return "Connection Successful"
        case .failure: return "Connection Failed"
        }
    }

    private var buttonBackground: Color {
        switch connectionStatus {
        case .idle, .testing: return ColorPalette.primary
        case .success: return ColorPalette.success
        case .failure: return ColorPalette.error
        }
    }

    private var buttonTextColor: Color {
        switch connectionStatus {
        case .success, .failure: return .white
        default: return ColorPalette.backgroundDark
        }
    }

    private func testConnection() {
        // Cancel any pending reset task
        resetTask?.cancel()

        connectionStatus = .testing
        connectedHostname = nil
        connectedVersion = nil

        Task {
            do {
                let systemInfo = try await UnraidService.shared.testConnection(
                    url: editingURL,
                    apiKey: editingAPIKey
                )
                await MainActor.run {
                    connectedHostname = systemInfo.hostname
                    connectedVersion = systemInfo.version
                    connectionStatus = .success
                    // Only save settings on successful connection
                    saveSettings()
                    resetStatusAfterDelay()
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failure(error.localizedDescription)
                    // Don't save invalid settings
                    resetStatusAfterDelay()
                }
            }
        }
    }

    private func resetStatusAfterDelay() {
        // Cancel any existing reset task
        resetTask?.cancel()

        resetTask = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await MainActor.run {
                    if case .idle = connectionStatus { return }
                    connectionStatus = .idle
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    #if DEBUG
    private func discoverSchema() {
        Task {
            // First, query the array with all possible capacity fields
            let testQuery = """
            query {
                array {
                    state
                    capacity {
                        disks { total used free }
                    }
                }
            }
            """
            print("=== TESTING CAPACITY QUERY ===")
            print(testQuery)

            do {
                let schema = try await UnraidService.shared.introspectSchema(
                    url: editingURL,
                    apiKey: editingAPIKey
                )
                print("=== UNRAID GRAPHQL SCHEMA ===")
                // Pretty print the JSON
                if let data = schema.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    print(prettyString)
                } else {
                    print(schema)
                }
                print("=== END SCHEMA ===")
            } catch {
                print("Schema discovery failed: \(error)")
            }
        }
    }
    #endif
}

// MARK: - Requirement Row

private struct RequirementRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            Text(text)
                .font(AppTypography.caption1())
                .foregroundColor(ColorPalette.textSecondaryDark)
        }
    }
}

#Preview {
    NavigationView {
        UnraidSettingsView()
    }
    .preferredColorScheme(.dark)
}
