import Foundation

struct MovieImage: Codable, Hashable {
    let coverType: String
    let url: String
    let remoteUrl: String?
}

struct Movie: Codable, Identifiable, Hashable {
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
    let runtime: Int
    var monitored: Bool
    let status: String
    let images: [MovieImage]
    let tmdbId: Int?
    var qualityProfileId: Int?
    var added: String?
    var digitalRelease: String?
    var physicalRelease: String?
    var inCinemas: String?

    init(
        id: Int,
        title: String,
        year: Int,
        overview: String?,
        runtime: Int,
        monitored: Bool,
        status: String,
        images: [MovieImage],
        tmdbId: Int? = nil,
        qualityProfileId: Int? = nil,
        added: String? = nil,
        digitalRelease: String? = nil,
        physicalRelease: String? = nil,
        inCinemas: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.runtime = runtime
        self.monitored = monitored
        self.status = status
        self.images = images
        self.tmdbId = tmdbId
        self.qualityProfileId = qualityProfileId
        self.added = added
        self.digitalRelease = digitalRelease
        self.physicalRelease = physicalRelease
        self.inCinemas = inCinemas
    }

    /// Parse added date string to Date
    var addedDate: Date? {
        guard let added = added else { return nil }
        if let date = Self.iso8601Formatter.date(from: added) {
            return date
        }
        return Self.iso8601FormatterSimple.date(from: added)
    }

    /// Check if movie is coming soon (not yet released)
    var isComingSoon: Bool {
        status == "announced" || status == "inCinemas"
    }

}

struct MovieLookup: Codable, Identifiable {
    var id: Int { tmdbId }
    var radarrId: Int?
    let tmdbId: Int
    let title: String
    let year: Int
    let overview: String?
    let runtime: Int
    let images: [MovieImage]?

    enum CodingKeys: String, CodingKey {
        case radarrId = "id"
        case tmdbId, title, year, overview, runtime, images
    }
}

// MARK: - Movie File Models (Radarr API)

struct MovieFileQuality: Codable, Hashable {
    let quality: MovieFileQualityInfo
}

struct MovieFileQualityInfo: Codable, Hashable {
    let id: Int
    let name: String
    let resolution: Int?
}

struct MovieFileMediaInfo: Codable, Hashable {
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

struct MovieFile: Codable, Identifiable, Hashable {
    let id: Int
    let movieId: Int
    let relativePath: String?
    let path: String?
    let size: Int64
    let dateAdded: String?
    let quality: MovieFileQuality?
    let mediaInfo: MovieFileMediaInfo?
    let releaseGroup: String?

    /// Formatted file size string (e.g., "4.2 GB")
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Quality name (e.g., "Bluray-1080p")
    var qualityName: String {
        quality?.quality.name ?? "Unknown"
    }

    /// Video codec (e.g., "x265")
    var videoCodec: String? {
        mediaInfo?.videoCodec
    }

    /// Audio codec (e.g., "DTS-HD MA")
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

// MARK: - Manual Release Search Models

struct ReleaseSearchResult: Codable, Identifiable, Hashable {
    let guid: String
    let title: String
    let indexerId: Int?
    let indexer: String?
    let size: Int64?
    let age: Int?
    let ageHours: Double?
    let seeders: Int?
    let leechers: Int?
    let approved: Bool?
    let rejected: Bool?
    let rejections: [String]?
    let quality: MovieFileQuality?

    var id: String { "\(indexerId ?? 0)-\(guid)" }

    var formattedSize: String {
        guard let size else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var qualityName: String {
        quality?.quality.name ?? "Unknown"
    }

    var ageDisplay: String {
        if let age, age >= 1 {
            return "\(age)d"
        }
        if let ageHours {
            return "\(Int(ageHours))h"
        }
        return ""
    }

    var rejectionSummary: String {
        rejections?.joined(separator: ", ") ?? ""
    }
}

// MARK: - Root Folder Model (Radarr API)

struct RootFolder: Codable, Identifiable, Hashable {
    let id: Int
    let path: String
    let freeSpace: Int64?
    let totalSpace: Int64?

    /// Formatted free space string (e.g., "500 GB free")
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

// MARK: - Quality Profile Model (Radarr API)

struct RadarrQualityProfile: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Queue Models (Radarr API)

struct QueueItem: Codable, Identifiable, Hashable {
    let id: Int
    let movieId: Int?
    let seriesId: Int?
    let episodeId: Int?
    let title: String
    let status: String
    let trackedDownloadStatus: String?
    let trackedDownloadState: String?
    let statusMessages: [QueueStatusMessage]?
    let size: Double
    let sizeleft: Double
    let timeleft: String?
    let estimatedCompletionTime: String?
    let protocol_: String?
    let downloadClient: String?
    let indexer: String?

    enum CodingKeys: String, CodingKey {
        case id, movieId, seriesId, episodeId, title, status
        case trackedDownloadStatus, trackedDownloadState
        case statusMessages, size, sizeleft, timeleft
        case estimatedCompletionTime
        case protocol_ = "protocol"
        case downloadClient, indexer
    }

    /// Progress percentage (0-100)
    var progress: Double {
        guard size > 0 else { return 0 }
        return ((size - sizeleft) / size) * 100
    }

    /// Formatted size string
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// Formatted remaining size
    var formattedRemaining: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeleft))
    }

    /// Whether download is stalled or has issues
    var hasIssue: Bool {
        trackedDownloadStatus == "warning" || trackedDownloadStatus == "error"
    }

    /// Status display text
    var statusDisplay: String {
        if let state = trackedDownloadState {
            return state.capitalized
        }
        return status.capitalized
    }
}

struct QueueStatusMessage: Codable, Hashable {
    let title: String?
    let messages: [String]?
}

struct QueueResponse: Codable {
    let page: Int
    let pageSize: Int
    let totalRecords: Int
    let records: [QueueItem]
}
