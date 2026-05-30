//
//  ServerBackup.swift
//  Media Manager
//
//  Model for Radarr/Sonarr server backups
//

import Foundation

/// Represents a backup from Radarr or Sonarr server
struct ServerBackup: Codable, Identifiable, Hashable {
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
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    let id: Int
    let name: String
    let path: String
    let type: String
    let size: Int64
    let time: String

    /// Formatted backup date
    var formattedDate: String {
        if let date = Self.iso8601Formatter.date(from: time) {
            return Self.displayFormatter.string(from: date)
        }
        if let date = Self.iso8601FormatterSimple.date(from: time) {
            return Self.displayFormatter.string(from: date)
        }
        return time
    }

    /// Formatted backup size
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Backup type display name
    var typeDisplayName: String {
        switch type.lowercased() {
        case "scheduled":
            return "Scheduled"
        case "manual":
            return "Manual"
        case "update":
            return "Update"
        default:
            return type.capitalized
        }
    }
}
