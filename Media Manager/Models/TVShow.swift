import Foundation

/// Quality profile from Sonarr
struct QualityProfile: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Monitor options for adding TV shows to Sonarr
enum MonitorOption: String, CaseIterable, Identifiable {
    case all = "all"
    case firstSeason = "firstSeason"
    case latestSeason = "latestSeason"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Seasons"
        case .firstSeason: return "First Season Only"
        case .latestSeason: return "Latest Season"
        case .none: return "None"
        }
    }

    var description: String {
        switch self {
        case .all: return "Monitor all seasons and episodes"
        case .firstSeason: return "Only monitor the first season"
        case .latestSeason: return "Only monitor the most recent season"
        case .none: return "Don't monitor any episodes"
        }
    }
}

struct TVShowImage: Codable, Hashable {
    let coverType: String
    let url: String
    let remoteUrl: String?
}

struct TVShowStatistics: Codable, Hashable {
    let seasonCount: Int?
    let episodeCount: Int?
    let episodeFileCount: Int?
    let totalEpisodeCount: Int?
    let sizeOnDisk: Int64?
    let percentOfEpisodes: Double?
}

struct TVShow: Codable, Identifiable, Hashable {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterSimple: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let id: Int
    let title: String
    let year: Int
    let overview: String?
    let network: String?
    let status: String
    var monitored: Bool
    var qualityProfileId: Int
    let images: [TVShowImage]
    let statistics: TVShowStatistics?
    let tvdbId: Int?
    var added: String?
    var firstAired: String?
    var nextAiring: String?

    init(
        id: Int,
        title: String,
        year: Int,
        overview: String?,
        network: String?,
        status: String,
        monitored: Bool,
        qualityProfileId: Int,
        images: [TVShowImage],
        statistics: TVShowStatistics?,
        tvdbId: Int? = nil,
        added: String? = nil,
        firstAired: String? = nil,
        nextAiring: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.network = network
        self.status = status
        self.monitored = monitored
        self.qualityProfileId = qualityProfileId
        self.images = images
        self.statistics = statistics
        self.tvdbId = tvdbId
        self.added = added
        self.firstAired = firstAired
        self.nextAiring = nextAiring
    }

    // Convenience computed properties
    var seasonCount: Int {
        statistics?.seasonCount ?? 0
    }

    var episodeCount: Int {
        statistics?.episodeCount ?? 0
    }

    /// Parse added date string to Date
    var addedDate: Date? {
        guard let added = added else { return nil }
        if let date = Self.iso8601Formatter.date(from: added) {
            return date
        }
        return Self.iso8601FormatterSimple.date(from: added)
    }

    /// Check if show has upcoming episodes
    var isComingSoon: Bool {
        guard let nextAiring = nextAiring else { return false }
        if let date = Self.iso8601Formatter.date(from: nextAiring) {
            return date > Date()
        }
        if let date = Self.iso8601FormatterSimple.date(from: nextAiring) {
            return date > Date()
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(monitored)
        hasher.combine(qualityProfileId)
    }

    static func == (lhs: TVShow, rhs: TVShow) -> Bool {
        lhs.id == rhs.id &&
        lhs.monitored == rhs.monitored &&
        lhs.qualityProfileId == rhs.qualityProfileId
    }
}

struct TVShowLookup: Codable, Identifiable {
    var id: Int { tvdbId }
    let tvdbId: Int
    let title: String
    let year: Int
    let overview: String?
    let statistics: TVShowStatistics?
    let network: String?
    let images: [TVShowImage]?

    enum CodingKeys: String, CodingKey {
        case tvdbId, title, year, overview, statistics, network, images
    }

    var seasonCount: Int {
        statistics?.seasonCount ?? 0
    }
}

// MARK: - Episode File Models (Sonarr API)

struct EpisodeFileQuality: Codable, Hashable {
    let quality: EpisodeFileQualityInfo
}

struct EpisodeFileQualityInfo: Codable, Hashable {
    let id: Int
    let name: String
    let resolution: Int?
}

struct EpisodeFileMediaInfo: Codable, Hashable {
    let videoBitDepth: Int?
    let videoBitrate: Int?
    let videoCodec: String?
    let videoFps: Double?
    let resolution: String?
    let runTime: String?
    let scanType: String?
    let audioBitrate: Int?
    let audioChannels: Double?
    let audioCodec: String?
    let audioLanguages: String?
    let audioStreamCount: Int?
    let subtitles: String?
}

struct EpisodeFile: Codable, Identifiable, Hashable {
    let id: Int
    let seriesId: Int
    let seasonNumber: Int
    let relativePath: String?
    let path: String?
    let size: Int64
    let dateAdded: String?
    let quality: EpisodeFileQuality?
    let mediaInfo: EpisodeFileMediaInfo?
    let releaseGroup: String?

    /// Formatted file size string (e.g., "1.2 GB")
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Quality name (e.g., "HDTV-720p")
    var qualityName: String {
        quality?.quality.name ?? "Unknown"
    }

    /// Video codec (e.g., "x264")
    var videoCodec: String? {
        mediaInfo?.videoCodec
    }

    /// Audio codec (e.g., "AAC")
    var audioCodec: String? {
        mediaInfo?.audioCodec
    }

    /// File name from path
    var fileName: String {
        if let path = path {
            return (path as NSString).lastPathComponent
        }
        if let relativePath = relativePath {
            return (relativePath as NSString).lastPathComponent
        }
        return "Unknown file"
    }
}

/// Represents a season with its episode files for display
struct SeasonFiles: Identifiable, Hashable {
    let seasonNumber: Int
    let files: [EpisodeFile]

    var id: Int { seasonNumber }

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

// MARK: - Embedded Series Info (for wanted/missing endpoint)

struct EmbeddedSeries: Codable, Hashable {
    let id: Int
    let title: String
    let year: Int?
}

// MARK: - Episode Model (Sonarr API)

struct Episode: Codable, Identifiable, Hashable {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterSimple: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let id: Int
    let seriesId: Int
    let tvdbId: Int?
    let episodeFileId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String?
    let airDate: String?
    let airDateUtc: String?
    let overview: String?
    let hasFile: Bool
    let monitored: Bool
    let absoluteEpisodeNumber: Int?
    let sceneAbsoluteEpisodeNumber: Int?
    let sceneEpisodeNumber: Int?
    let sceneSeasonNumber: Int?
    let unverifiedSceneNumbering: Bool?
    let series: EmbeddedSeries?

    /// Episode code (e.g., "S01E05")
    var episodeCode: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    /// Display title with episode code
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return "\(episodeCode) - \(title)"
        }
        return episodeCode
    }

    /// Parse air date to Date object
    var airDateParsed: Date? {
        guard let airDateUtc = airDateUtc else { return nil }
        if let date = Self.iso8601Formatter.date(from: airDateUtc) {
            return date
        }
        return Self.iso8601FormatterSimple.date(from: airDateUtc)
    }

    /// Whether episode has aired
    var hasAired: Bool {
        guard let airDate = airDateParsed else { return false }
        return airDate <= Date()
    }

    /// Episode status for display
    var statusDisplay: String {
        if hasFile {
            return "Downloaded"
        } else if !hasAired {
            return "Unaired"
        } else if monitored {
            return "Missing"
        } else {
            return "Unmonitored"
        }
    }

    /// Status color
    var statusColor: String {
        if hasFile {
            return "success" // green
        } else if !hasAired {
            return "info" // blue
        } else if monitored {
            return "error" // red - missing
        } else {
            return "muted" // gray
        }
    }
}

// MARK: - Season Model (Sonarr API)

struct Season: Codable, Identifiable, Hashable {
    let seasonNumber: Int
    var monitored: Bool
    let statistics: SeasonStatistics?

    var id: Int { seasonNumber }

    /// Season display name
    var displayName: String {
        if seasonNumber == 0 {
            return "Specials"
        }
        return "Season \(seasonNumber)"
    }
}

struct SeasonStatistics: Codable, Hashable {
    let episodeFileCount: Int?
    let episodeCount: Int?
    let totalEpisodeCount: Int?
    let sizeOnDisk: Int64?
    let percentOfEpisodes: Double?

    /// Number of missing episodes
    var missingCount: Int {
        let total = episodeCount ?? 0
        let downloaded = episodeFileCount ?? 0
        return max(0, total - downloaded)
    }
}

// MARK: - Root Folder Model (Sonarr API)

struct SonarrRootFolder: Codable, Identifiable, Hashable {
    let id: Int
    let path: String
    let freeSpace: Int64?
    let totalSpace: Int64?

    /// Formatted free space string
    var formattedFreeSpace: String {
        guard let freeSpace = freeSpace else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: freeSpace) + " free"
    }

    /// Folder name from path
    var folderName: String {
        (path as NSString).lastPathComponent
    }
}
