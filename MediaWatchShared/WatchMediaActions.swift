import Foundation

enum WatchConnectivityKey {
    nonisolated static let command = "command"
    nonisolated static let payload = "payload"
    nonisolated static let snapshot = "snapshot"
}

enum WatchConnectivityCommand {
    nonisolated static let addMedia = "addMedia"
    nonisolated static let refreshSnapshot = "refreshSnapshot"
    nonisolated static let searchMedia = "searchMedia"
    nonisolated static let toggleDownloads = "toggleDownloads"
}

enum WatchMediaKind: String, Codable, CaseIterable, Identifiable {
    case movie
    case tvShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie:
            return "Movie"
        case .tvShow:
            return "TV Show"
        }
    }
}

struct WatchMediaSearchRequest: Codable, Equatable {
    var id: UUID
    var kind: WatchMediaKind
    var query: String
}

struct WatchMediaSearchResponse: Codable, Equatable {
    var requestId: UUID
    var kind: WatchMediaKind
    var query: String
    var results: [WatchMediaSearchResult]
    var errorMessage: String?

    static func failure(
        request: WatchMediaSearchRequest,
        message: String
    ) -> WatchMediaSearchResponse {
        WatchMediaSearchResponse(
            requestId: request.id,
            kind: request.kind,
            query: request.query,
            results: [],
            errorMessage: message
        )
    }
}

struct WatchMediaAddRequest: Codable, Equatable {
    var id: UUID
    var result: WatchMediaSearchResult
}

struct WatchMediaAddResponse: Codable, Equatable {
    var requestId: UUID
    var resultId: String
    var success: Bool
    var message: String
}

struct WatchMediaSearchResult: Codable, Equatable, Identifiable {
    var kind: WatchMediaKind
    var remoteId: Int
    var title: String
    var year: Int
    var subtitle: String
    var overview: String?
    var runtime: Int?
    var seasonCount: Int?
    var network: String?

    var id: String {
        "\(kind.rawValue)-\(remoteId)"
    }

    var displayTitle: String {
        year > 0 ? "\(title) (\(year))" : title
    }
}
