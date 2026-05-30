import SwiftUI

struct SabNZBSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared
    @State private var editingURL: String = ""
    @State private var editingAPIKey: String = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var testAttemptId = UUID()

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle("SabNZB Settings")
        .onAppear(perform: loadSettings)
        .onDisappear(perform: saveSettingsSilently)
        #if !os(tvOS)
        .navBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    saveSettingsSilently()
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
    }

    // MARK: - tvOS Content
    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            VStack(spacing: TVSizing.sectionSpacing) {
                // Connection Section
                TVSettingsSection(title: "Connection") {
                    VStack(spacing: AppSpacing.lg) {
                        TVTextFieldCard(
                            label: "Server URL",
                            placeholder: "http://sabnzbd.example.com:8080",
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
                if case .failure(let message) = connectionStatus {
                    TVStatusMessage(message: message, type: .error)
                }

                if case .success = connectionStatus {
                    TVStatusMessage(message: "Connected successfully!", type: .success)
                }

                // Help Section
                TVSettingsSection(title: "Help") {
                    TVHelpCard(service: .sabnzb)
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

                SettingsSection(title: "Connection", footer: "Enter the full URL to your SABnzbd instance and your API key.") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Server URL")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .frame(width: 100, alignment: .leading)

                            TextField("http://sabnzb.example.com:8080", text: $editingURL)
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

                        APIKeyHelpButton(service: .sabnzb)
                            .padding()
                    }
                }

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
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
        }
    }
    #endif

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

    private func loadSettings() {
        editingURL = configuration.sabnzbURL
        editingAPIKey = configuration.sabnzbAPIKey
    }

    private func saveSettingsSilently() {
        try? configuration.saveSabNZB(url: editingURL, apiKey: editingAPIKey)
    }

    private func testConnection() {
        connectionStatus = .testing
        let currentAttempt = UUID()
        testAttemptId = currentAttempt

        Task {
            do {
                try await SabNZBService.shared.testConnection(url: editingURL, apiKey: editingAPIKey)
                await MainActor.run {
                    saveSettingsSilently()
                    connectionStatus = .success
                    resetStatusAfterDelay(attemptId: currentAttempt)
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failure("Could not connect to server")
                    resetStatusAfterDelay(attemptId: currentAttempt)
                }
            }
        }
    }

    private func resetStatusAfterDelay(attemptId: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard testAttemptId == attemptId else { return }
            connectionStatus = .idle
        }
    }
}

#Preview {
    NavigationView {
        SabNZBSettingsView()
    }
    .preferredColorScheme(.dark)
}
