import SwiftUI

struct TMDBSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared
    @State private var editingAccessToken: String = ""
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
        .navigationTitle("TMDB Settings")
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
                // Authentication Section
                TVSettingsSection(title: "Authentication") {
                    TVTextFieldCard(
                        label: "Read Access Token",
                        placeholder: "Enter your TMDB token (starts with eyJ...)",
                        text: $editingAccessToken,
                        icon: "key.fill",
                        isSecure: true
                    )
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

                // About Section
                TVSettingsSection(title: "About TMDB") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(ColorPalette.info)

                            Text("The Movie Database (TMDB) provides trending movies and TV shows data for the Dashboard.")
                                .font(.system(size: 24))
                                .foregroundColor(ColorPalette.textSecondaryDark)
                        }
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
                    TVHelpCard(service: .tmdb)
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

                SettingsSection(title: "Authentication", footer: "Enter your TMDB Read Access Token. You can get one for free at themoviedb.org.") {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Read Access Token")
                                .font(AppTypography.body())
                                .foregroundColor(ColorPalette.textPrimaryDark)

                            TextField("Enter token...", text: $editingAccessToken, axis: .vertical)
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.textSecondaryDark)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .lineLimit(3...6)
                        }
                        .padding()

                        Divider()
                            .background(ColorPalette.divider)

                        APIKeyHelpButton(service: .tmdb)
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

                // Info section
                SettingsSection(title: "About TMDB", footer: nil) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("The Movie Database (TMDB) provides trending movies and TV shows data for the Dashboard.")
                            .font(AppTypography.caption1())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                    .padding()
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
        editingAccessToken = configuration.tmdbAccessToken
    }

    private func saveSettingsSilently() {
        try? configuration.saveTMDBToken(editingAccessToken)
    }

    private func testConnection() {
        connectionStatus = .testing
        let currentAttempt = UUID()
        testAttemptId = currentAttempt

        Task {
            do {
                try await TMDBService.shared.testConnection(token: editingAccessToken)
                await MainActor.run {
                    saveSettingsSilently()
                    connectionStatus = .success
                    resetStatusAfterDelay(attemptId: currentAttempt)
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failure("Could not connect to TMDB")
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
        TMDBSettingsView()
    }
    .preferredColorScheme(.dark)
}
