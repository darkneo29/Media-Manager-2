import Foundation

struct WatchDashboardSnapshot: Codable, Equatable {
    var generatedAt: Date
    var configuration: WatchConfigurationSummary
    var library: WatchLibrarySummary
    var services: [WatchServiceSummary]
    var downloads: WatchDownloadsSummary
    var upcoming: [WatchUpcomingItem]

    static let empty = WatchDashboardSnapshot(
        generatedAt: .distantPast,
        configuration: WatchConfigurationSummary(
            radarrConfigured: false,
            sonarrConfigured: false,
            sabnzbdConfigured: false,
            unraidConfigured: false
        ),
        library: WatchLibrarySummary(movieCount: 0, showCount: 0),
        services: [],
        downloads: .notConfigured,
        upcoming: []
    )

    static let preview = WatchDashboardSnapshot(
        generatedAt: Date(),
        configuration: WatchConfigurationSummary(
            radarrConfigured: true,
            sonarrConfigured: true,
            sabnzbdConfigured: true,
            unraidConfigured: false
        ),
        library: WatchLibrarySummary(movieCount: 128, showCount: 42),
        services: [
            WatchServiceSummary(id: "radarr", name: "Radarr", state: .ready, detail: "128 movies"),
            WatchServiceSummary(id: "sonarr", name: "Sonarr", state: .ready, detail: "42 shows"),
            WatchServiceSummary(id: "sabnzbd", name: "SabNZB", state: .ready, detail: "2 active")
        ],
        downloads: WatchDownloadsSummary(
            isConfigured: true,
            isPaused: false,
            speedBytesPerSecond: 4_800_000,
            activeCount: 2,
            queuedCount: 5,
            items: [
                WatchDownloadItem(
                    id: "preview-1",
                    name: "Example Movie",
                    status: "Downloading",
                    progress: 62,
                    timeLeft: "12m",
                    speedBytesPerSecond: 3_100_000
                ),
                WatchDownloadItem(
                    id: "preview-2",
                    name: "Example Show S02E04",
                    status: "Queued",
                    progress: 0,
                    timeLeft: "--",
                    speedBytesPerSecond: 0
                )
            ],
            errorMessage: nil
        ),
        upcoming: [
            WatchUpcomingItem(
                id: "preview-release-1",
                title: "Dune: Part Three",
                date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                kind: "Movie",
                detail: "Digital Release",
                mediaId: 1
            ),
            WatchUpcomingItem(
                id: "preview-release-2",
                title: "Severance",
                date: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                kind: "TV",
                detail: "New Episode",
                mediaId: 2
            )
        ]
    )

    var hasAnyConfiguredService: Bool {
        configuration.radarrConfigured ||
        configuration.sonarrConfigured ||
        configuration.sabnzbdConfigured ||
        configuration.unraidConfigured
    }
}

struct WatchConfigurationSummary: Codable, Equatable {
    var radarrConfigured: Bool
    var sonarrConfigured: Bool
    var sabnzbdConfigured: Bool
    var unraidConfigured: Bool
}

struct WatchLibrarySummary: Codable, Equatable {
    var movieCount: Int
    var showCount: Int
}

struct WatchServiceSummary: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var state: WatchServiceState
    var detail: String
}

enum WatchServiceState: String, Codable, Equatable {
    case ready
    case warning
    case notConfigured
}

struct WatchDownloadsSummary: Codable, Equatable {
    var isConfigured: Bool
    var isPaused: Bool
    var speedBytesPerSecond: Int64
    var activeCount: Int
    var queuedCount: Int
    var items: [WatchDownloadItem]
    var errorMessage: String?

    static let notConfigured = WatchDownloadsSummary(
        isConfigured: false,
        isPaused: false,
        speedBytesPerSecond: 0,
        activeCount: 0,
        queuedCount: 0,
        items: [],
        errorMessage: nil
    )

    var statusText: String {
        guard isConfigured else { return "Not configured" }
        if let errorMessage { return errorMessage }
        if isPaused { return "Paused" }
        if activeCount > 0 { return "\(activeCount) active" }
        if queuedCount > 0 { return "\(queuedCount) queued" }
        return "Idle"
    }
}

struct WatchDownloadItem: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var status: String
    var progress: Double
    var timeLeft: String
    var speedBytesPerSecond: Int64

    var progressFraction: Double {
        min(max(progress / 100, 0), 1)
    }
}

struct WatchUpcomingItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var date: Date
    var kind: String
    var detail: String
    var mediaId: Int

    var relativeDateText: String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let releaseDay = calendar.startOfDay(for: date)

        guard let days = calendar.dateComponents([.day], from: startOfToday, to: releaseDay).day else {
            return formattedDate
        }

        switch days {
        case ..<0:
            return "Released"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case 2...6:
            return "In \(days) days"
        default:
            return formattedDate
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

extension Int64 {
    var watchFormattedBytesPerSecond: String {
        guard self > 0 else { return "0 KB/s" }

        let value = Double(self)
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB/s", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB/s", value / 1_000)
        }
        return "\(self) B/s"
    }
}
