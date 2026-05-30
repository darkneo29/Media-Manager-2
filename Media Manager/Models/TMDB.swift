import Foundation

// MARK: - Trending Movie

struct TrendingMovie: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
    }

    /// Extract year from release date string (format: "YYYY-MM-DD")
    var year: Int? {
        guard let releaseDate = releaseDate,
              releaseDate.count >= 4,
              let year = Int(releaseDate.prefix(4)) else {
            return nil
        }
        return year
    }

    /// Full poster URL for TMDB CDN
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    /// Full backdrop URL for TMDB CDN
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(path)")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrendingMovie, rhs: TrendingMovie) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Trending TV Show

struct TrendingTVShow: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    /// TVDB ID fetched from external IDs API (not from trending API).
    /// Must be set manually after fetching external IDs from TMDB - not included in trending/search responses.
    var tvdbId: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        // tvdbId is excluded - populated separately
    }

    /// Extract year from first air date string (format: "YYYY-MM-DD")
    var year: Int? {
        guard let firstAirDate = firstAirDate,
              firstAirDate.count >= 4,
              let year = Int(firstAirDate.prefix(4)) else {
            return nil
        }
        return year
    }

    /// Full poster URL for TMDB CDN
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    /// Full backdrop URL for TMDB CDN
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(path)")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrendingTVShow, rhs: TrendingTVShow) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - API Response Wrapper

struct TMDBPagedResponse<T: Codable>: Codable {
    let page: Int
    let results: [T]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

// MARK: - Video/Trailer Models

struct TMDBVideo: Codable, Identifiable {
    let id: String
    let name: String
    let key: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, key, site, type, official
        case publishedAt = "published_at"
    }

    /// Returns YouTube URL if the video is hosted on YouTube
    var youtubeURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    /// Returns true if this is a trailer
    var isTrailer: Bool {
        type.lowercased() == "trailer"
    }

    /// Returns true if this is an official video
    var isOfficial: Bool {
        official ?? false
    }
}

struct TMDBVideosResponse: Codable {
    let id: Int
    let results: [TMDBVideo]
}

// MARK: - External IDs (for TVDB to TMDB lookup)

struct TMDBExternalIds: Codable {
    let id: Int?
    let tvdbId: Int?
    let imdbId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tvdbId = "tvdb_id"
        case imdbId = "imdb_id"
    }
}

struct TMDBFindResponse: Codable {
    let tvResults: [TMDBTVResult]

    enum CodingKeys: String, CodingKey {
        case tvResults = "tv_results"
    }
}

struct TMDBTVResult: Codable, Identifiable {
    let id: Int
    let name: String
}
