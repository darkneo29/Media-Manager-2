//
//  DeepLinkHandler.swift
//  Media Manager
//
//  Handles deep links from widgets and other sources.
//  URL scheme: mediamanager://movie/{id} or mediamanager://tvshow/{id}
//

import SwiftUI
import Observation

/// Deep link destination types
enum DeepLinkDestination: Equatable {
    case movie(id: Int)
    case tvShow(id: Int)
    case calendar
    case downloads
    case settings
}

/// Handles deep link parsing and navigation state
@MainActor
@Observable
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    /// The pending destination to navigate to
    var pendingDestination: DeepLinkDestination?

    /// A backup document waiting for the Settings restore flow to consume it.
    var pendingBackupURL: URL?

    private init() {}

    /// Parse a deep link URL and set the pending destination
    /// - Parameter url: The URL to parse (e.g., mediamanager://movie/123)
    func handle(url: URL) {
        if url.isFileURL {
            let supportedExtensions = [BackupService.fileExtension, "json"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return }

            pendingBackupURL = url
            pendingDestination = .settings
            return
        }

        guard url.scheme == "mediamanager" else { return }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "movie":
            if let idString = pathComponents.first, let id = Int(idString) {
                pendingDestination = .movie(id: id)
            }
        case "tvshow":
            if let idString = pathComponents.first, let id = Int(idString) {
                pendingDestination = .tvShow(id: id)
            }
        case "calendar":
            pendingDestination = .calendar
        case "downloads":
            pendingDestination = .downloads
        case "settings":
            pendingDestination = .settings
        default:
            break
        }
    }

    /// Clear the pending destination after navigation is complete
    func clearPendingDestination() {
        pendingDestination = nil
    }

    func clearPendingBackupURL() {
        pendingBackupURL = nil
    }
}
