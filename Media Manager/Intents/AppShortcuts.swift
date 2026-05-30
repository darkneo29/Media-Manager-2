import AppIntents

/// Provides App Shortcuts for Dragon Media Manager
/// These shortcuts appear in the Shortcuts app and can be triggered via Siri
struct MediaManagerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Add Movie shortcut (prompts for title)
        AppShortcut(
            intent: AddMovieIntent(),
            phrases: [
                "Add a movie to \(.applicationName)",
                "Add movie in \(.applicationName)",
                "Add a movie to Radarr in \(.applicationName)"
            ],
            shortTitle: "Add Movie",
            systemImageName: "film.fill"
        )

        // Quick Add Movie shortcut
        AppShortcut(
            intent: QuickAddMovieIntent(),
            phrases: [
                "Quick add movie to \(.applicationName)",
                "Quickly add a movie in \(.applicationName)"
            ],
            shortTitle: "Quick Add Movie",
            systemImageName: "film.badge.plus"
        )

        // Add TV Show shortcut (prompts for title)
        AppShortcut(
            intent: AddTVShowIntent(),
            phrases: [
                "Add a TV show to \(.applicationName)",
                "Add TV show in \(.applicationName)",
                "Add a series to Sonarr in \(.applicationName)"
            ],
            shortTitle: "Add TV Show",
            systemImageName: "tv.fill"
        )

        // Quick Add TV Show shortcut
        AppShortcut(
            intent: QuickAddTVShowIntent(),
            phrases: [
                "Quick add TV show to \(.applicationName)",
                "Quickly add a series in \(.applicationName)"
            ],
            shortTitle: "Quick Add TV Show",
            systemImageName: "tv.badge.plus"
        )

        // Download status shortcuts
        AppShortcut(
            intent: GetDownloadQueueStatusIntent(),
            phrases: [
                "Check download status in \(.applicationName)",
                "Get downloads in \(.applicationName)",
                "Show download queue in \(.applicationName)"
            ],
            shortTitle: "Download Status",
            systemImageName: "arrow.down.circle"
        )

        AppShortcut(
            intent: PauseResumeDownloadsIntent(),
            phrases: [
                "Pause downloads in \(.applicationName)",
                "Resume downloads in \(.applicationName)",
                "Toggle downloads in \(.applicationName)"
            ],
            shortTitle: "Pause/Resume Downloads",
            systemImageName: "playpause"
        )

        // Library and releases shortcuts
        AppShortcut(
            intent: GetUpcomingReleasesIntent(),
            phrases: [
                "Get upcoming releases in \(.applicationName)",
                "What's coming soon in \(.applicationName)",
                "Show upcoming movies in \(.applicationName)"
            ],
            shortTitle: "Upcoming Releases",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: GetLibraryStatsIntent(),
            phrases: [
                "Get library stats in \(.applicationName)",
                "How many movies in \(.applicationName)",
                "Show library count in \(.applicationName)"
            ],
            shortTitle: "Library Stats",
            systemImageName: "film.stack"
        )

        // Server status shortcut
        AppShortcut(
            intent: GetServerStatusIntent(),
            phrases: [
                "Get server status in \(.applicationName)",
                "Check Unraid status in \(.applicationName)",
                "Show server info in \(.applicationName)"
            ],
            shortTitle: "Server Status",
            systemImageName: "server.rack"
        )
    }
}
