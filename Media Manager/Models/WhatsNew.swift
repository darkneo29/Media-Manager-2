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
            id: "2026-09-15-version-3.0-build-19",
            title: "Version 3.0 Build 19",
            subtitle: "New OS 27 features with continued OS 26 support",
            entries: [
                WhatsNewEntry(
                    id: "os27-library-assistant",
                    kind: .newFeature,
                    title: "Library Assistant on iOS 27",
                    description: "Search movies and shows together from Home, with Spotlight helping find related matches. On supported devices, ask on-device AI questions about a sample of your library or identify a title from a photo when image support is available."
                ),
                WhatsNewEntry(
                    id: "os27-siri-spotlight",
                    kind: .newFeature,
                    title: "More Ways to Find Your Library",
                    description: "On iOS 27, library titles appear in Spotlight, Siri can open in-app library search, and movie and show screens share title context with supported system actions."
                ),
                WhatsNewEntry(
                    id: "exact-shortcut-title-actions",
                    kind: .improvement,
                    title: "More Accurate Siri and Shortcuts Actions",
                    description: "Ask Siri to add a movie or TV show by title, with clearer follow-up choices for matching titles. Selected-title and Quick Add actions keep your saved preferences, and successful adds appear in your library immediately."
                ),
                WhatsNewEntry(
                    id: "configurable-upcoming-widget",
                    kind: .newFeature,
                    title: "Choose Your Widget Releases",
                    description: "Configure the Upcoming widget to show all releases, movies only, or TV shows only. Available on OS 26 and OS 27."
                ),
                WhatsNewEntry(
                    id: "watch27-library-summary",
                    kind: .newFeature,
                    title: "Library Summaries on Apple Watch",
                    description: "On watchOS 27, request a library and download summary from your paired iPhone. A supported iPhone can use on-device AI to rewrite the summary, with a factual summary available when AI is unavailable."
                ),
                WhatsNewEntry(
                    id: "os26-compatibility-os27-appearance",
                    kind: .improvement,
                    title: "Ready for OS 27, Still at Home on OS 26",
                    description: "Navigation adopts the system appearance on iOS 27 while OS 26 keeps its familiar experience. Existing library browsing, downloads, and media controls remain available on OS 26."
                )
            ]
        ),
        WhatsNewRelease(
            id: "2026-09-07-version-2.10",
            title: "Version 2.10",
            subtitle: "A refreshed Apple Watch experience",
            entries: [
                WhatsNewEntry(
                    id: "watch-focused-navigation",
                    kind: .improvement,
                    title: "Simpler Watch Navigation",
                    description: "Open Find & Add, Downloads, Upcoming, and Services from a focused home screen, with clearer guidance when connecting your iPhone for the first time."
                ),
                WhatsNewEntry(
                    id: "watch-media-details",
                    kind: .improvement,
                    title: "Review Before Adding",
                    description: "Search by voice or text, open a title to read its details, and add it using your saved iPhone settings. Added titles stay marked In library."
                ),
                WhatsNewEntry(
                    id: "watch-download-controls",
                    kind: .improvement,
                    title: "Better Watch Downloads",
                    description: "The download queue refreshes automatically while visible, with explicit pause and resume controls and feedback when a change cannot be confirmed."
                ),
                WhatsNewEntry(
                    id: "watch-connection-recovery",
                    kind: .fix,
                    title: "Clearer Connection Feedback",
                    description: "Initial sync waits for the iPhone connection, pending offline refreshes are reused, and unanswered searches and adds show recovery guidance."
                )
            ]
        ),
        WhatsNewRelease(
            id: "2026-09-05-version-2.8",
            title: "Version 2.8",
            subtitle: "Automatic download updates and a faster library",
            entries: [
                WhatsNewEntry(
                    id: "downloads-more-menu-refresh",
                    kind: .fix,
                    title: "Automatic Download Updates",
                    description: "Active downloads refresh when you open Downloads and every five seconds while visible, including when opened through the iPhone More menu."
                ),
                WhatsNewEntry(
                    id: "accurate-show-matching",
                    kind: .fix,
                    title: "More Accurate TV Show Matching",
                    description: "TVDB IDs and release years keep remakes and shows with similar titles from being mistaken for items already in your library."
                ),
                WhatsNewEntry(
                    id: "faster-recent-library",
                    kind: .improvement,
                    title: "Faster Recent Items",
                    description: "The dashboard reuses recent-item results and avoids unnecessary sorting and date parsing for large libraries."
                ),
                WhatsNewEntry(
                    id: "image-cache-memory",
                    kind: .improvement,
                    title: "Better Image Memory Management",
                    description: "The image cache now accounts for Retina image sizes when managing its memory budget."
                )
            ]
        ),
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
                    id: "live-sabnzb-queue",
                    kind: .improvement,
                    title: "Live SABnzbd Queue",
                    description: "Active downloads load immediately and update every five seconds while the Downloads tab is visible, with uncached queue data and a clear Live indicator."
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
