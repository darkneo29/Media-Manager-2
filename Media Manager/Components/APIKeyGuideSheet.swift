import SwiftUI

/// Represents the type of service for API key guidance
enum APIKeyGuideService {
    case radarr
    case sonarr
    case sabnzb
    case tmdb
    case unraid

    var title: String {
        switch self {
        case .radarr: return "Radarr API Key"
        case .sonarr: return "Sonarr API Key"
        case .sabnzb: return "SABnzbd API Key"
        case .tmdb: return "TMDB Read Access Token"
        case .unraid: return "Unraid API Key"
        }
    }

    var icon: String {
        switch self {
        case .radarr: return "film.fill"
        case .sonarr: return "tv.fill"
        case .sabnzb: return "arrow.down.circle.fill"
        case .tmdb: return "star.fill"
        case .unraid: return "server.rack"
        }
    }

    var iconColor: Color {
        switch self {
        case .radarr: return ColorPalette.warning
        case .sonarr: return ColorPalette.info
        case .sabnzb: return ColorPalette.success
        case .tmdb: return Color(red: 0.09, green: 0.82, blue: 0.64) // TMDB green
        case .unraid: return ColorPalette.primary
        }
    }

    var steps: [APIKeyGuideStep] {
        switch self {
        case .radarr:
            return [
                APIKeyGuideStep(number: 1, text: "Open Radarr in your web browser"),
                APIKeyGuideStep(number: 2, text: "Go to Settings (gear icon)"),
                APIKeyGuideStep(number: 3, text: "Click on General"),
                APIKeyGuideStep(number: 4, text: "Scroll down to the Security section"),
                APIKeyGuideStep(number: 5, text: "Copy the API Key shown there")
            ]
        case .sonarr:
            return [
                APIKeyGuideStep(number: 1, text: "Open Sonarr in your web browser"),
                APIKeyGuideStep(number: 2, text: "Go to Settings (gear icon)"),
                APIKeyGuideStep(number: 3, text: "Click on General"),
                APIKeyGuideStep(number: 4, text: "Scroll down to the Security section"),
                APIKeyGuideStep(number: 5, text: "Copy the API Key shown there")
            ]
        case .sabnzb:
            return [
                APIKeyGuideStep(number: 1, text: "Open SABnzbd in your web browser"),
                APIKeyGuideStep(number: 2, text: "Click the Config icon (gear/wrench)"),
                APIKeyGuideStep(number: 3, text: "Go to General → Security"),
                APIKeyGuideStep(number: 4, text: "Copy the API Key shown there"),
                APIKeyGuideStep(number: 5, text: "Tip: The API key is also visible in SABnzbd's URL bar")
            ]
        case .tmdb:
            return [
                APIKeyGuideStep(number: 1, text: "Go to themoviedb.org and sign in (or create a free account)"),
                APIKeyGuideStep(number: 2, text: "Click your profile icon → Settings"),
                APIKeyGuideStep(number: 3, text: "Click API in the left sidebar"),
                APIKeyGuideStep(number: 4, text: "Request an API key if you haven't already"),
                APIKeyGuideStep(number: 5, text: "Copy the Read Access Token (the longer one, starts with 'eyJ...')")
            ]
        case .unraid:
            return [
                APIKeyGuideStep(number: 1, text: "Open your Unraid web interface"),
                APIKeyGuideStep(number: 2, text: "Go to Settings → Management Access"),
                APIKeyGuideStep(number: 3, text: "Click on API Keys"),
                APIKeyGuideStep(number: 4, text: "Create a new key with 'viewer' role or higher"),
                APIKeyGuideStep(number: 5, text: "Copy the generated API Key")
            ]
        }
    }

    var notes: [String] {
        switch self {
        case .radarr:
            return ["Requires Radarr v3 or later"]
        case .sonarr:
            return ["Requires Sonarr v3 or later"]
        case .sabnzb:
            return ["Use the full API key, not the NZB key"]
        case .tmdb:
            return [
                "Use the Read Access Token (v4 auth), not the API Key (v3)",
                "The token is much longer than the API key",
                "TMDB is free for personal use"
            ]
        case .unraid:
            return [
                "Requires Unraid 7.2+ with built-in API",
                "For Unraid 6.x, install the Unraid Connect plugin first"
            ]
        }
    }

    var externalURL: URL? {
        switch self {
        case .tmdb:
            return URL(string: "https://www.themoviedb.org/settings/api")
        default:
            return nil
        }
    }

    var externalURLLabel: String? {
        switch self {
        case .tmdb:
            return "Open TMDB API Settings"
        default:
            return nil
        }
    }
}

/// Represents a single step in the API key guide
struct APIKeyGuideStep: Identifiable {
    let id = UUID()
    let number: Int
    let text: String
}

/// A sheet view that provides step-by-step instructions for obtaining API keys
struct APIKeyGuideSheet: View {
    let service: APIKeyGuideService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Header with icon
                        VStack(spacing: AppSpacing.sm) {
                            Image(systemName: service.icon)
                                .font(.system(size: 48))
                                .foregroundColor(service.iconColor)

                            Text(service.title)
                                .font(AppTypography.title2(.bold))
                                .foregroundColor(ColorPalette.textPrimaryDark)
                        }
                        .padding(.top, AppSpacing.lg)

                        // Steps section
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Steps")
                                .font(AppTypography.headline(.semibold))
                                .foregroundColor(ColorPalette.textPrimaryDark)

                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                ForEach(service.steps) { step in
                                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                                        Text("\(step.number)")
                                            .font(AppTypography.caption1(.bold))
                                            .foregroundColor(ColorPalette.backgroundDark)
                                            .frame(width: 24, height: 24)
                                            .background(service.iconColor)
                                            .clipShape(Circle())

                                        Text(step.text)
                                            .font(AppTypography.body())
                                            .foregroundColor(ColorPalette.textSecondaryDark)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(ColorPalette.cardBackgroundDark)
                        .cornerRadius(AppRadius.md)

                        // Notes section
                        if !service.notes.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(ColorPalette.info)
                                    Text("Notes")
                                        .font(AppTypography.headline(.semibold))
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                }

                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    ForEach(service.notes, id: \.self) { note in
                                        HStack(alignment: .top, spacing: AppSpacing.xs) {
                                            Text("•")
                                                .foregroundColor(ColorPalette.textMutedDark)
                                            Text(note)
                                                .font(AppTypography.caption1())
                                                .foregroundColor(ColorPalette.textSecondaryDark)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(ColorPalette.info.opacity(0.1))
                            .cornerRadius(AppRadius.md)
                        }

                        // External link button (e.g., for TMDB)
                        if let url = service.externalURL, let label = service.externalURLLabel {
                            Link(destination: url) {
                                HStack {
                                    Text(label)
                                        .font(AppTypography.body(.semibold))
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(service.iconColor)
                                .cornerRadius(AppRadius.md)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(ColorPalette.secondary)
                }
            }
        }
    }
}

/// A button that shows the API key guide when tapped
struct APIKeyHelpButton: View {
    let service: APIKeyGuideService
    @State private var showingGuide = false

    var body: some View {
        Button(action: { showingGuide = true }) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "questionmark.circle")
                Text("How to get your API key")
            }
            .font(AppTypography.caption1())
            .foregroundColor(ColorPalette.secondary)
        }
        .sheet(isPresented: $showingGuide) {
            APIKeyGuideSheet(service: service)
        }
    }
}

#Preview("Radarr Guide") {
    APIKeyGuideSheet(service: .radarr)
        .preferredColorScheme(.dark)
}

#Preview("TMDB Guide") {
    APIKeyGuideSheet(service: .tmdb)
        .preferredColorScheme(.dark)
}

#Preview("Help Button") {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()
        APIKeyHelpButton(service: .radarr)
    }
    .preferredColorScheme(.dark)
}
