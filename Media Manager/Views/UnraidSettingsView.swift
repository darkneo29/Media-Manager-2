import SwiftUI

struct UnraidSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared

    // Local state for editing (avoids lag from @AppStorage writes on every keystroke)
    @State private var editingURL: String = ""
    @State private var editingAPIKey: String = ""
    @State private var showMediaStackFirst: Bool = true
    @AppStorage("unraidStorageWarningPercent") private var storageWarningPercent = 10
    @State private var temperatureUnit: String = "celsius"

    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectedHostname: String?
    @State private var testedCapabilities: UnraidCapabilities?
    @State private var connectedVersion: String?
    @State private var resetTask: Task<Void, Never>?
    @State private var testAttemptId = UUID()
    @State private var saveError: String?

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .alert("Could not save Unraid settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) { saveError = nil } }
        message: { Text(saveError ?? "") }
        .navigationTitle("Unraid Settings")
        #if !os(tvOS)
        .navBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if saveSettings() { dismiss() }
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
        .onChange(of: editingURL) { _, _ in invalidateConnectionTest() }
        .onChange(of: editingAPIKey) { _, _ in invalidateConnectionTest() }
        .onDisappear {
            // Cancel any pending reset task
            resetTask?.cancel()
            testAttemptId = UUID()
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

                if let testedCapabilities { UnraidAccessSummary(capabilities: testedCapabilities) }

                // Display Preferences Section
                TVSettingsSection(title: "Display Preferences") {
                    VStack(spacing: AppSpacing.lg) {
                        // Media Stack First Toggle
                        TVToggleCard(
                            title: "Media Stack First",
                            subtitle: "Show Radarr, Sonarr, etc. at the top",
                            isOn: $showMediaStackFirst
                        )

                        storageWarningSettings

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
                            text: "Viewer access for monitoring; Docker/VM update permission for controls"
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

                if let testedCapabilities { UnraidAccessSummary(capabilities: testedCapabilities).padding(.horizontal, AppSpacing.md) }

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

                        storageWarningSettings

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
                            text: "Viewer access for monitoring; Docker/VM update permission for controls"
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

    private var storageWarningSettings: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Picker("Low-space warning", selection: $storageWarningPercent) {
                Text("Off").tag(0)
                ForEach([5, 10, 15, 20, 25], id: \.self) { percent in
                    Text("\(percent)% free or less").tag(percent)
                }
            }
            Text("Applies to array, data disks, and cache filesystems. Critical at 5% free or less. Warnings appear in the app when current readings are available.")
                .font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
        }
        .padding()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        editingURL = configuration.unraidURL
        editingAPIKey = configuration.unraidAPIKey
        showMediaStackFirst = defaults.object(forKey: "unraidShowMediaStackFirst") as? Bool ?? true
        temperatureUnit = defaults.string(forKey: "unraidTemperatureUnit") ?? "celsius"
    }

    @discardableResult
    private func saveSettings() -> Bool {
        do {
            try configuration.saveUnraid(url: editingURL, apiKey: editingAPIKey)
            saveDisplayPreferences()
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func invalidateConnectionTest() {
        testAttemptId = UUID()
        resetTask?.cancel()
        testedCapabilities = nil
        connectedHostname = nil
        connectedVersion = nil
        connectionStatus = .idle
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
        testedCapabilities = nil
        connectedHostname = nil
        connectedVersion = nil
        let currentAttempt = UUID()
        testAttemptId = currentAttempt
        let testedURL = editingURL
        let testedAPIKey = editingAPIKey

        Task {
            do {
                let systemInfo = try await UnraidService.shared.testConnection(
                    url: testedURL,
                    apiKey: testedAPIKey
                )
                let endpoint = try UnraidService.graphQLURL(from: testedURL)
                let inspector = UnraidService(credentials: { (endpoint, testedAPIKey) })
                let capabilities = try await inspector.fetchCapabilities(forceRefresh: true)
                await MainActor.run {
                    guard testAttemptId == currentAttempt,
                          editingURL == testedURL,
                          editingAPIKey == testedAPIKey else { return }
                    do {
                        try configuration.saveUnraid(url: testedURL, apiKey: testedAPIKey)
                        saveDisplayPreferences()
                        testedCapabilities = capabilities
                        connectedHostname = systemInfo.hostname
                        connectedVersion = systemInfo.version
                        connectionStatus = .success
                    } catch {
                        connectionStatus = .failure("Connected, but settings could not be saved: \(error.localizedDescription)")
                    }
                    resetStatusAfterDelay()
                }
            } catch {
                await MainActor.run {
                    guard testAttemptId == currentAttempt,
                          editingURL == testedURL,
                          editingAPIKey == testedAPIKey else { return }
                    connectionStatus = .failure(error.localizedDescription)
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
