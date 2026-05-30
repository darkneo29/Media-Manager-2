import Foundation

enum DownloadStatus: String, Codable {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case extracting = "Extracting"
    case verifying = "Verifying"
    case repairing = "Repairing"
    case fetching = "Fetching"
    case propagating = "Propagating"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Try exact match first, then case-insensitive
        if let status = DownloadStatus(rawValue: rawValue) {
            self = status
        } else {
            self = DownloadStatus(from: rawValue)
        }
    }

    /// Initialize from SabNZB status string
    init(from sabStatus: String) {
        switch sabStatus.lowercased() {
        case "downloading":
            self = .downloading
        case "paused":
            self = .paused
        case "queued":
            self = .queued
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "extracting", "unpacking":
            self = .extracting
        case "verifying":
            self = .verifying
        case "repairing":
            self = .repairing
        case "fetching":
            self = .fetching
        case "propagating":
            self = .propagating
        default:
            self = .queued
        }
    }
}

struct Download: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let status: DownloadStatus
    let progress: Double // 0-100
    let size: Int64 // Total size in bytes
    let sizeLeft: Int64 // Remaining bytes
    let timeLeft: String // Human readable time (e.g., "5m 30s")
    let speed: Int64 // Download speed in bytes/sec
}

struct DownloadQueue: Codable {
    let paused: Bool
    let speedLimit: Int? // Speed limit in KB/s, nil if unlimited
    let speed: Int64 // Current download speed in bytes/sec
    let downloads: [Download]
}

// MARK: - History Models

struct HistoryDownload: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let status: DownloadStatus
    let size: Int64 // Total size in bytes
    let completedAt: Date?
    let downloadTime: Int // Download time in seconds
    let failMessage: String?
}

// MARK: - SabNZB API Response Models

/// Response from SabNZB queue API
struct SabNZBQueueResponse: Codable {
    let queue: SabNZBQueueData
}

struct SabNZBQueueData: Codable {
    let paused: Bool
    let speedlimit: String
    let speed: String // e.g., "5.2 M" for MB/s
    let kbpersec: String // KB/s as string
    let slots: [SabNZBQueueSlot]
}

struct SabNZBQueueSlot: Codable {
    let nzo_id: String
    let filename: String
    let cat: String
    let status: String
    let percentage: String
    let mb: String // Total MB
    let mbleft: String // MB remaining
    let timeleft: String
}

/// Response from SabNZB history API
struct SabNZBHistoryResponse: Codable {
    let history: SabNZBHistoryData
}

struct SabNZBHistoryData: Codable {
    let slots: [SabNZBHistorySlot]
}

struct SabNZBHistorySlot: Codable {
    let nzo_id: String
    let name: String
    let category: String
    let status: String
    let bytes: Int64
    let completed: Int // Unix timestamp
    let download_time: Int // Seconds
    let fail_message: String?
}

// MARK: - SabNZB Warnings Models

/// App-level warning model for display
struct SabNZBWarning: Identifiable, Hashable {
    let id: String
    let type: String
    let text: String
    let time: Int // Unix timestamp

    var date: Date {
        Date(timeIntervalSince1970: Double(time))
    }
}

/// Response from SabNZB warnings API
struct SabNZBWarningsResponse: Codable {
    let warnings: [SabNZBWarningData]
}

struct SabNZBWarningData: Codable {
    let type: String
    let text: String
    let time: Int
}
