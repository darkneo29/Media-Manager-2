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
            id: "2026-06-29-build-8",
            title: "Version 2.7 Build 8",
            subtitle: "Guided adding, deeper Radarr and Sonarr controls, and richer activity tracking",
            entries: [
                WhatsNewEntry(
                    id: "guided-add-workflows",
                    kind: .newFeature,
                    title: "Guided Movie and TV Adds",
                    description: "Choose Download Now, Monitor Only, Add Only, or Future Episodes presets, review a confirmation summary, and expand advanced options only when you need them."
                ),
                WhatsNewEntry(
                    id: "shared-add-defaults",
                    kind: .improvement,
                    title: "Defaults Shared Everywhere",
                    description: "Quality profiles, root folders, monitoring, search behavior, series settings, and tags are remembered and shared by full adds, Discover, Quick Add, Siri, and Apple Watch."
                ),
                WhatsNewEntry(
                    id: "radarr-collections",
                    kind: .newFeature,
                    title: "Radarr Collections",
                    description: "Browse movie collections, change collection monitoring, search for missing titles, and control whether newly added collection movies are monitored and searched."
                ),
                WhatsNewEntry(
                    id: "expanded-editing-tools",
                    kind: .improvement,
                    title: "Deeper Movie and Show Editing",
                    description: "Change quality profiles and root folders, optionally move existing files, refresh and scan, rename files, and search individual TV seasons directly from detail screens."
                ),
                WhatsNewEntry(
                    id: "bulk-library-actions",
                    kind: .newFeature,
                    title: "Bulk Library Actions",
                    description: "Update monitoring and quality profiles, search multiple movies or shows, and remove selected library items using Radarr and Sonarr's native editor operations."
                ),
                WhatsNewEntry(
                    id: "activity-wanted-management",
                    kind: .newFeature,
                    title: "Activity, Wanted, and Blocklist",
                    description: "Downloads now includes Radarr and Sonarr queue, history, and blocklist views plus Missing and Cutoff Unmet lists with direct search actions."
                ),
                WhatsNewEntry(
                    id: "complete-sonarr-calendar",
                    kind: .improvement,
                    title: "Complete TV Episode Calendar",
                    description: "The calendar now loads Sonarr's full date range so every scheduled episode appears instead of showing only each series' next airing."
                ),
                WhatsNewEntry(
                    id: "safer-media-operations",
                    kind: .fix,
                    title: "Safer Adds and Queue Actions",
                    description: "Exact Radarr and Sonarr IDs prevent duplicate or mismatched adds, errors stay visible without hiding results, and queue removal clearly offers Remove Only or Remove and Block Release."
                )
            ]
        ),
        WhatsNewRelease(
            id: "2026-06-28",
            title: "Version 2.7",
            subtitle: "Reliability, setup, and widget deep-link fixes",
            entries: [
                WhatsNewEntry(
                    id: "connection-recovery",
                    kind: .improvement,
                    title: "Clearer Connection Recovery",
                    description: "Home, Discover, Downloads, Movies, and TV Shows now show actionable retry states when a server or TMDB request fails instead of falling back to empty screens."
                ),
                WhatsNewEntry(
                    id: "server-settings-refresh",
                    kind: .fix,
                    title: "More Reliable Server Settings",
                    description: "Saved server URLs are normalized and Radarr, Sonarr, TMDB, image, library, and widget caches refresh when credentials or endpoints change."
                ),
                WhatsNewEntry(
                    id: "add-flow-guards",
                    kind: .fix,
                    title: "Safer Add Flows",
                    description: "Movie and show add screens now wait for quality profiles and root folders, show retry banners when options fail, and add successful items to the local library immediately."
                ),
                WhatsNewEntry(
                    id: "fresh-refreshes",
                    kind: .improvement,
                    title: "Fresh Manual Refreshes",
                    description: "Manual retries and refreshes now bypass stale in-flight cache requests for Radarr, Sonarr, and TMDB so the newest server response wins."
                ),
                WhatsNewEntry(
                    id: "widget-deep-links",
                    kind: .fix,
                    title: "Widget Deep Links Fixed",
                    description: "Upcoming release widget links now use the correct library identifiers and retry navigation after the matching movie or show finishes loading."
                ),
                WhatsNewEntry(
                    id: "service-error-details",
                    kind: .fix,
                    title: "Better Service Error Details",
                    description: "SABnzbd authentication, download history failures, and Unraid GraphQL errors now surface clearer messages for faster troubleshooting."
                ),
                WhatsNewEntry(
                    id: "version-settings-cleanup",
                    kind: .improvement,
                    title: "Version and Settings Cleanup",
                    description: "The app now reports its current version and build in Settings, removes placeholder legal links, and opens the real project GitHub link."
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
