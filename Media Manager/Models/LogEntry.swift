import Foundation

/// Represents a log entry from Radarr or Sonarr
struct LogEntry: Codable, Identifiable, Hashable {
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

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss a"
        return formatter
    }()

    let id: Int
    let time: String
    let level: String
    let logger: String?
    let message: String
    let exception: String?
    let exceptionType: String?

    /// Returns a formatted timestamp for display
    var formattedTime: String {
        if let date = Self.iso8601Formatter.date(from: time) {
            return Self.displayFormatter.string(from: date)
        }
        if let date = Self.iso8601FormatterSimple.date(from: time) {
            return Self.displayFormatter.string(from: date)
        }
        return time
    }

    /// Returns the appropriate color for the log level
    var levelColor: String {
        switch level.lowercased() {
        case "error", "fatal":
            return "error"
        case "warn", "warning":
            return "warning"
        case "info":
            return "info"
        case "debug", "trace":
            return "debug"
        default:
            return "info"
        }
    }
}

/// Response wrapper for log API calls
struct LogResponse: Codable {
    let page: Int
    let pageSize: Int
    let sortKey: String
    let sortDirection: String
    let totalRecords: Int
    let records: [LogEntry]
}
