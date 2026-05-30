import Foundation

enum WhatsNewEntryKind: String, Hashable {
    case newFeature = "New"
    case improvement = "Improved"
    case fix = "Fixed"

    var systemImage: String {
        switch self {
        case .newFeature:
            return "sparkles"
        case .improvement:
            return "arrow.up.circle.fill"
        case .fix:
            return "wrench.and.screwdriver.fill"
        }
    }
}

struct WhatsNewEntry: Identifiable, Hashable {
    let id: String
    let kind: WhatsNewEntryKind
    let title: String
    let description: String
}

struct WhatsNewRelease: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let entries: [WhatsNewEntry]
}

enum WhatsNewCatalog {
    // Keep the newest release first so Settings can summarize the latest changes.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            id: "2026-04-26",
            title: "Version 2.5",
            subtitle: "Deeper Radarr and Sonarr library management",
            entries: [
                WhatsNewEntry(
                    id: "safe-delete-options",
                    kind: .newFeature,
                    title: "Safer Delete Controls",
                    description: "Movie and TV show deletes now offer clear choices to remove items only, delete files, or delete files and add an exclusion."
                ),
                WhatsNewEntry(
                    id: "file-inspector",
                    kind: .newFeature,
                    title: "Expanded File Details",
                    description: "Movie and episode file cards now show richer media details including path, runtime, resolution, languages, subtitles, and date added."
                ),
                WhatsNewEntry(
                    id: "episode-management",
                    kind: .newFeature,
                    title: "Episode-Level Management",
                    description: "TV show details now support episode monitor toggles, season monitor actions, single-episode searches, and manual release lookup."
                ),
                WhatsNewEntry(
                    id: "manual-release-search",
                    kind: .newFeature,
                    title: "Manual Release Picker",
                    description: "Manual search results now surface quality, size, indexer, age, seeders, and rejection reasons before grabbing a release."
                ),
                WhatsNewEntry(
                    id: "bulk-library-actions",
                    kind: .improvement,
                    title: "Bulk Library Actions",
                    description: "Movie and TV show lists now include selection mode for bulk monitor changes, quality profile updates, searches, and safe deletes."
                )
            ]
        ),
        WhatsNewRelease(
            id: "2026-04-19",
            title: "April 19, 2026",
            subtitle: "Trailer previews before adding new movies and shows",
            entries: [
                WhatsNewEntry(
                    id: "pre-add-trailers",
                    kind: .newFeature,
                    title: "Watch Trailers Before Adding",
                    description: "Search results for new movies and TV shows now include a Watch Trailer button, so trailers can be opened before adding anything to your library."
                )
            ]
        ),
        WhatsNewRelease(
            id: "2026-04-18",
            title: "April 18, 2026",
            subtitle: "Release Radar, in-app update tracking, and a brand refresh",
            entries: [
                WhatsNewEntry(
                    id: "release-radar",
                    kind: .newFeature,
                    title: "Release Radar",
                    description: "Follow movies and shows, prioritize upcoming releases on the dashboard, and filter the calendar by theater, digital, physical, or TV events."
                ),
                WhatsNewEntry(
                    id: "whats-new-log",
                    kind: .improvement,
                    title: "What's New in Settings",
                    description: "Added a dedicated update log in Settings so new features and improvements can be tracked inside the app as they ship."
                ),
                WhatsNewEntry(
                    id: "launch-screen-refresh",
                    kind: .improvement,
                    title: "Launch Screen Refresh",
                    description: "Replaced the legacy mascot splash art with a darker, logo-led launch screen that matches the new Dragon brand."
                )
            ]
        )
    ]

    static var latestRelease: WhatsNewRelease? {
        releases.first
    }

    static var latestSummary: String {
        guard let latestRelease else {
            return "No updates logged yet"
        }

        let entryCount = latestRelease.entries.count
        return "\(entryCount) recent update\(entryCount == 1 ? "" : "s")"
    }
}
