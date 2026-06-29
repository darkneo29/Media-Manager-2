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
    case moving = "Moving"
    case running = "Running"
    case quickCheck = "Quick Check"

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
        switch sabStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
        case "moving":
            self = .moving
        case "running":
            self = .running
        case "quick check", "quickcheck":
            self = .quickCheck
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
struct SabNZBQueueResponse: Decodable {
    let queue: SabNZBQueueData
}

struct SabNZBQueueData: Decodable {
    let paused: Bool
    let pausedAll: Bool
    let speedlimit: String
    let speed: String // e.g., "5.2 M" for MB/s
    let kbpersec: String // KB/s as string
    let slots: [SabNZBQueueSlot]

    enum CodingKeys: String, CodingKey {
        case paused
        case pausedAll = "paused_all"
        case speedlimit
        case speed
        case kbpersec
        case slots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paused = container.sabBool(forKey: .paused)
        pausedAll = container.sabBool(forKey: .pausedAll)
        speedlimit = container.sabString(forKey: .speedlimit)
        speed = container.sabString(forKey: .speed)
        kbpersec = container.sabString(forKey: .kbpersec)
        slots = (try? container.decodeIfPresent([SabNZBQueueSlot].self, forKey: .slots)) ?? []
    }
}

struct SabNZBQueueSlot: Decodable {
    let nzo_id: String
    let filename: String
    let cat: String
    let status: String
    let percentage: String
    let mb: String // Total MB
    let mbleft: String // MB remaining
    let timeleft: String

    enum CodingKeys: String, CodingKey {
        case nzo_id
        case filename
        case name
        case cat
        case category
        case status
        case percentage
        case mb
        case mbleft
        case timeleft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolvedName = container.sabString(forKey: .filename, fallbackKey: .name)
        nzo_id = container.sabString(forKey: .nzo_id, default: resolvedName)
        filename = resolvedName
        cat = container.sabString(forKey: .cat, fallbackKey: .category)
        status = container.sabString(forKey: .status, default: "Queued")
        percentage = container.sabString(forKey: .percentage, default: "0")
        mb = container.sabString(forKey: .mb, default: "0")
        mbleft = container.sabString(forKey: .mbleft, default: "0")
        timeleft = container.sabString(forKey: .timeleft, default: "--")
    }
}

/// Response from SabNZB history API
struct SabNZBHistoryResponse: Decodable {
    let history: SabNZBHistoryData
}

struct SabNZBHistoryData: Decodable {
    let slots: [SabNZBHistorySlot]

    enum CodingKeys: String, CodingKey {
        case slots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slots = (try? container.decodeIfPresent([SabNZBHistorySlot].self, forKey: .slots)) ?? []
    }
}

struct SabNZBHistorySlot: Decodable {
    let nzo_id: String
    let name: String
    let category: String
    let status: String
    let bytes: Int64
    let completed: Int // Unix timestamp
    let download_time: Int // Seconds
    let fail_message: String?

    enum CodingKeys: String, CodingKey {
        case nzo_id
        case name
        case filename
        case category
        case cat
        case status
        case bytes
        case downloaded
        case size
        case completed
        case completedAt = "completed_at"
        case download_time
        case downloadTime
        case fail_message
        case failMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.sabString(forKey: .name, fallbackKey: .filename)
        category = container.sabString(forKey: .category, fallbackKey: .cat)
        status = container.sabString(forKey: .status, default: "Completed")

        let decodedBytes = container.sabInt64(forKey: .bytes, fallbackKey: .downloaded)
        bytes = decodedBytes > 0 ? decodedBytes : SabNZBHistorySlot.parseByteCount(container.sabString(forKey: .size))

        completed = container.sabInt(forKey: .completed, fallbackKey: .completedAt)
        download_time = container.sabInt(forKey: .download_time, fallbackKey: .downloadTime)
        fail_message = container.sabOptionalString(forKey: .fail_message) ?? container.sabOptionalString(forKey: .failMessage)

        let stableFallbackID = [name, String(completed)]
            .filter { !$0.isEmpty && $0 != "0" }
            .joined(separator: "-")
        nzo_id = container.sabString(forKey: .nzo_id, default: stableFallbackID)
    }

    private static func parseByteCount(_ rawValue: String) -> Int64 {
        let cleaned = rawValue
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return 0 }

        let numberPart = cleaned.prefix { character in
            character.isNumber || character == "."
        }
        guard let value = Double(numberPart) else { return 0 }

        let unit = cleaned.dropFirst(numberPart.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let multiplier: Double
        if unit.hasPrefix("t") {
            multiplier = 1024 * 1024 * 1024 * 1024
        } else if unit.hasPrefix("g") {
            multiplier = 1024 * 1024 * 1024
        } else if unit.hasPrefix("m") {
            multiplier = 1024 * 1024
        } else if unit.hasPrefix("k") {
            multiplier = 1024
        } else {
            multiplier = 1
        }

        return Int64(value * multiplier)
    }
}

private extension KeyedDecodingContainer {
    func sabOptionalString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func sabString(forKey key: Key, fallbackKey: Key? = nil, default defaultValue: String = "") -> String {
        if let value = sabOptionalString(forKey: key), !value.isEmpty {
            return value
        }
        if let fallbackKey, let value = sabOptionalString(forKey: fallbackKey), !value.isEmpty {
            return value
        }
        return defaultValue
    }

    func sabInt(forKey key: Key, fallbackKey: Key? = nil, default defaultValue: Int = 0) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        if let fallbackKey {
            return sabInt(forKey: fallbackKey, default: defaultValue)
        }
        return defaultValue
    }

    func sabInt64(forKey key: Key, fallbackKey: Key? = nil, default defaultValue: Int64 = 0) -> Int64 {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let intValue = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        if let fallbackKey {
            return sabInt64(forKey: fallbackKey, default: defaultValue)
        }
        return defaultValue
    }

    func sabBool(forKey key: Key, default defaultValue: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return defaultValue
            }
        }
        return defaultValue
    }
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
