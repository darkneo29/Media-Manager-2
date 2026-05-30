import Foundation
import Combine

enum ReleaseRadarEventFilter: String, CaseIterable, Codable, Identifiable, Hashable {
    case theatrical
    case digital
    case physical
    case tvEpisodes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theatrical:
            return "In Theaters"
        case .digital:
            return "Digital"
        case .physical:
            return "Physical"
        case .tvEpisodes:
            return "TV Episodes"
        }
    }

    var shortTitle: String {
        switch self {
        case .theatrical:
            return "Theaters"
        case .digital:
            return "Digital"
        case .physical:
            return "Physical"
        case .tvEpisodes:
            return "TV"
        }
    }

    var icon: String {
        switch self {
        case .theatrical:
            return "ticket.fill"
        case .digital:
            return "play.rectangle.fill"
        case .physical:
            return "shippingbox.fill"
        case .tvEpisodes:
            return "tv.fill"
        }
    }
}

final class ReleaseRadarService: ObservableObject {
    static let shared = ReleaseRadarService()

    @Published private(set) var followedMovieIds: Set<Int>
    @Published private(set) var followedShowIds: Set<Int>
    @Published private(set) var enabledFilters: Set<ReleaseRadarEventFilter>

    var hasCustomFilters: Bool {
        enabledFilters != Set(ReleaseRadarEventFilter.allCases)
    }

    private enum Keys {
        static let followedMovieIds = "releaseRadar.followedMovieIds"
        static let followedShowIds = "releaseRadar.followedShowIds"
        static let enabledFilters = "releaseRadar.enabledFilters"
    }

    private let userDefaults: UserDefaults

    private init() {
        let userDefaults = Self.makeUserDefaults()
        self.userDefaults = userDefaults
        self.followedMovieIds = Self.loadFollowedMovieIds(from: userDefaults)
        self.followedShowIds = Self.loadFollowedShowIds(from: userDefaults)
        self.enabledFilters = Self.loadEnabledFilters(from: userDefaults)
    }

    static func persistedFollowedMovieIds() -> Set<Int> {
        loadFollowedMovieIds(from: makeUserDefaults())
    }

    static func persistedFollowedShowIds() -> Set<Int> {
        loadFollowedShowIds(from: makeUserDefaults())
    }

    static func persistedEnabledFilters() -> Set<ReleaseRadarEventFilter> {
        loadEnabledFilters(from: makeUserDefaults())
    }

    static func eventFilter(for event: CalendarEvent) -> ReleaseRadarEventFilter {
        switch event.type {
        case .movieRelease(let releaseType):
            switch releaseType {
            case .theatrical:
                return .theatrical
            case .digital:
                return .digital
            case .physical:
                return .physical
            }
        case .tvEpisode:
            return .tvEpisodes
        }
    }

    func isFollowing(movieId: Int) -> Bool {
        followedMovieIds.contains(movieId)
    }

    func isFollowing(showId: Int) -> Bool {
        followedShowIds.contains(showId)
    }

    func isFollowing(movie: Movie) -> Bool {
        isFollowing(movieId: movie.id)
    }

    func isFollowing(show: TVShow) -> Bool {
        isFollowing(showId: show.id)
    }

    func isFollowing(event: CalendarEvent) -> Bool {
        switch event.source {
        case .movie(let movie):
            return isFollowing(movieId: movie.id)
        case .tvShow(let show):
            return isFollowing(showId: show.id)
        }
    }

    func isEnabled(for event: CalendarEvent) -> Bool {
        enabledFilters.contains(Self.eventFilter(for: event))
    }

    func filteredEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter(isEnabled(for:))
    }

    func toggleFollow(movie: Movie) {
        var ids = followedMovieIds
        if ids.contains(movie.id) {
            ids.remove(movie.id)
        } else {
            ids.insert(movie.id)
        }

        followedMovieIds = ids
        userDefaults.set(Array(ids).sorted(), forKey: Keys.followedMovieIds)
    }

    func toggleFollow(show: TVShow) {
        var ids = followedShowIds
        if ids.contains(show.id) {
            ids.remove(show.id)
        } else {
            ids.insert(show.id)
        }

        followedShowIds = ids
        userDefaults.set(Array(ids).sorted(), forKey: Keys.followedShowIds)
    }

    func toggleFilter(_ filter: ReleaseRadarEventFilter) {
        var nextFilters = enabledFilters

        if nextFilters.contains(filter) {
            guard nextFilters.count > 1 else { return }
            nextFilters.remove(filter)
        } else {
            nextFilters.insert(filter)
        }

        enabledFilters = nextFilters
        userDefaults.set(nextFilters.map(\.rawValue).sorted(), forKey: Keys.enabledFilters)
    }

    func enableAllFilters() {
        let allFilters = Set(ReleaseRadarEventFilter.allCases)
        guard enabledFilters != allFilters else { return }

        enabledFilters = allFilters
        userDefaults.set(allFilters.map(\.rawValue).sorted(), forKey: Keys.enabledFilters)
    }

    private static func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: WidgetDataService.appGroupIdentifier) ?? .standard
    }

    private static func loadFollowedMovieIds(from userDefaults: UserDefaults) -> Set<Int> {
        Set(userDefaults.array(forKey: Keys.followedMovieIds) as? [Int] ?? [])
    }

    private static func loadFollowedShowIds(from userDefaults: UserDefaults) -> Set<Int> {
        Set(userDefaults.array(forKey: Keys.followedShowIds) as? [Int] ?? [])
    }

    private static func loadEnabledFilters(from userDefaults: UserDefaults) -> Set<ReleaseRadarEventFilter> {
        let values = userDefaults.array(forKey: Keys.enabledFilters) as? [String] ?? []
        let filters = Set(values.compactMap(ReleaseRadarEventFilter.init(rawValue:)))
        return filters.isEmpty ? Set(ReleaseRadarEventFilter.allCases) : filters
    }
}
