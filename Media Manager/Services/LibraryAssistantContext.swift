import Foundation

enum LibraryAssistantContext {
    static func matches(_ query: String, title: String, overview: String?) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || title.localizedCaseInsensitiveContains(term) || (overview?.localizedCaseInsensitiveContains(term) ?? false)
    }

    /// Bound prompt size and exclude private server configuration and filesystem paths.
    static func make(movies: [Movie], shows: [TVShow], query: String) -> String {
        let tokens = query.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 3 }
        let rows = movies.map { ("Movie", $0.title, $0.year, $0.overview ?? "") }
            + shows.map { ("TV show", $0.title, $0.year, $0.overview ?? "") }
        let ranked = rows.enumerated().sorted { lhs, rhs in
            func score(_ row: (String, String, Int, String)) -> Int {
                let text = (row.1 + " " + row.3).lowercased()
                return tokens.filter { text.contains($0) }.count
            }
            let left = score(lhs.element), right = score(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        let sample = ranked.prefix(16).map { _, row in
            "\(row.0): \(row.1.prefix(120)) (\(row.2)): \(row.3.prefix(220))"
        }.joined(separator: "\n")
        return "Loaded library totals: \(movies.count) movies, \(shows.count) TV shows. Partial title sample:\n\(sample)"
    }
}
