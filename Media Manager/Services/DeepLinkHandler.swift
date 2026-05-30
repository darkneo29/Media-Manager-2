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
}

/// Handles deep link parsing and navigation state
@MainActor
@Observable
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    /// The pending destination to navigate to
    var pendingDestination: DeepLinkDestination?

    private init() {}

    /// Parse a deep link URL and set the pending destination
    /// - Parameter url: The URL to parse (e.g., mediamanager://movie/123)
    func handle(url: URL) {
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
        default:
            break
        }
    }

    /// Clear the pending destination after navigation is complete
    func clearPendingDestination() {
        pendingDestination = nil
    }
}
