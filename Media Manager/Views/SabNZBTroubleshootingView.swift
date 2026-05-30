import SwiftUI

struct SabNZBTroubleshootingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configuration = ConfigurationManager.shared
    @State private var showingWarnings = false
    @State private var warnings: [SabNZBWarning] = []
    @State private var isLoadingWarnings = false
    @State private var warningsError: String?
    @State private var isClearing = false
    @State private var clearSuccess = false
    @State private var clearError: String?

    private var isConfigured: Bool {
        configuration.isSabNZBConfigured
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
        .navigationTitle("SabNZB")
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
        .sheet(isPresented: $showingWarnings) {
            WarningsSheetView(
                warnings: warnings,
                isLoading: isLoadingWarnings,
                error: warningsError,
                onRefresh: fetchWarnings,
                onClear: clearWarnings
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
                    TVStatusMessage(message: "SabNZB is not configured. Please configure it in Settings first.", type: .error)

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
                                icon: "exclamationmark.triangle",
                                iconColor: ColorPalette.warning,
                                title: "View Warnings",
                                subtitle: "Recent server warnings"
                            ) {
                                showingWarnings = true
                                fetchWarnings()
                            }
                        }
                    }

                    if clearSuccess {
                        TVStatusMessage(message: "Warnings cleared successfully.", type: .success)
                    }

                    if let error = clearError {
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
        .fullScreenCover(isPresented: $showingWarnings) {
            TVWarningsView(
                warnings: warnings,
                isLoading: isLoadingWarnings,
                error: warningsError,
                onRefresh: fetchWarnings,
                onClear: clearWarnings,
                onDismiss: { showingWarnings = false }
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
                        Text("SabNZB Not Configured")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text("Please configure SabNZB in Settings first.")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, AppSpacing.xl)
                } else {
                    SettingsSection(title: "Warnings", footer: "View and clear warning messages from SabNZB.") {
                        Button(action: {
                            showingWarnings = true
                            fetchWarnings()
                        }) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(ColorPalette.warning)
                                Text("View Warnings")
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

                    // Clear status message
                    if clearSuccess {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorPalette.success)
                            Text("Warnings cleared successfully.")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.success)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    if let error = clearError {
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

    private func fetchWarnings() {
        isLoadingWarnings = true
        warningsError = nil

        Task {
            do {
                let fetchedWarnings = try await SabNZBService.shared.fetchWarnings(url: configuration.sabnzbURL, apiKey: configuration.sabnzbAPIKey)
                await MainActor.run {
                    warnings = fetchedWarnings
                    isLoadingWarnings = false
                }
            } catch {
                await MainActor.run {
                    warningsError = "Failed to fetch warnings: \(error.localizedDescription)"
                    isLoadingWarnings = false
                }
            }
        }
    }

    private func clearWarnings() {
        isClearing = true
        clearSuccess = false
        clearError = nil

        Task {
            do {
                try await SabNZBService.shared.clearWarnings(url: configuration.sabnzbURL, apiKey: configuration.sabnzbAPIKey)
                await MainActor.run {
                    isClearing = false
                    clearSuccess = true
                    warnings = []
                    resetClearStatusAfterDelay()
                }
            } catch {
                await MainActor.run {
                    isClearing = false
                    clearError = "Failed to clear warnings: \(error.localizedDescription)"
                    resetClearStatusAfterDelay()
                }
            }
        }
    }

    private func resetClearStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            clearSuccess = false
            clearError = nil
        }
    }
}

// MARK: - Warnings Sheet View

struct WarningsSheetView: View {
    let warnings: [SabNZBWarning]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.secondary))
                        .scaleEffect(1.2)
                } else if let error = error {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.error)
                        Text(error)
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            onRefresh()
                        }
                        .buttonStyle(.bordered)
                        .tint(ColorPalette.secondary)
                    }
                } else if warnings.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(ColorPalette.success)
                        Text("No Warnings")
                            .font(AppTypography.headline())
                            .foregroundColor(ColorPalette.textPrimaryDark)
                        Text("SabNZB has no active warnings.")
                            .font(AppTypography.body())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            ForEach(warnings) { warning in
                                WarningCard(warning: warning)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle("SabNZB Warnings")
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(ColorPalette.secondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.sm) {
                        if !warnings.isEmpty {
                            Button {
                                onClear()
                                dismiss()
                            } label: {
                                Text("Clear All")
                                    .foregroundColor(ColorPalette.error)
                            }
                        }

                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(ColorPalette.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Warning Card

struct WarningCard: View {
    let warning: SabNZBWarning

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: warning.date)
    }

    private var typeColor: Color {
        switch warning.type.lowercased() {
        case "error":
            return ColorPalette.error
        case "warning":
            return ColorPalette.warning
        default:
            return ColorPalette.info
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                // Type badge
                Text(warning.type.uppercased())
                    .font(AppTypography.caption2(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(typeColor)
                    .cornerRadius(AppRadius.sm)

                Spacer()

                // Timestamp
                Text(formattedDate)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            // Warning message
            Text(warning.text)
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textPrimaryDark)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }
}

// MARK: - tvOS Warnings View

#if os(tvOS)
struct TVWarningsView: View {
    let warnings: [SabNZBWarning]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: TVSizing.sectionSpacing) {
                // Header
                HStack {
                    Text("SabNZB Warnings")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    HStack(spacing: AppSpacing.lg) {
                        if !warnings.isEmpty {
                            Button("Clear All") {
                                onClear()
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Refresh") {
                            onRefresh()
                        }
                        .buttonStyle(.plain)

                        Button("Close") {
                            onDismiss()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TVSizing.contentPadding)
                .padding(.top, AppSpacing.xl)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    TVStatusMessage(message: error, type: .error)
                    Spacer()
                } else if warnings.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(ColorPalette.success)
                        Text("No Warnings")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(ColorPalette.textPrimaryDark)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(warnings) { warning in
                                TVWarningCard(warning: warning)
                            }
                        }
                        .padding(.horizontal, TVSizing.contentPadding)
                        .padding(.bottom, AppSpacing.xl)
                    }
                }
            }
        }
    }
}

struct TVWarningCard: View {
    let warning: SabNZBWarning

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: warning.date)
    }

    private var typeColor: Color {
        switch warning.type.lowercased() {
        case "error":
            return ColorPalette.error
        case "warning":
            return ColorPalette.warning
        default:
            return ColorPalette.info
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            // Type badge
            Text(warning.type.uppercased())
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(typeColor)
                .cornerRadius(AppRadius.sm)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(warning.text)
                    .font(.system(size: 24))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formattedDate)
                    .font(.system(size: 18))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            Spacer()
        }
        .padding(AppSpacing.lg)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
    }
}
#endif

#Preview {
    NavigationView {
        SabNZBTroubleshootingView()
    }
    .preferredColorScheme(.dark)
}
