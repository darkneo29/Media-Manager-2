import Foundation

enum MediaEntityResolution {
    static func exactCatalogMatches<Item>(_ items: [Item], term: String, prefix: String, id: KeyPath<Item, Int>) -> [Item] {
        var seen = Set<Int>()
        let items = items.filter { $0[keyPath: id] > 0 && seen.insert($0[keyPath: id]).inserted }
        guard term.lowercased().hasPrefix(prefix + ":") else { return items }
        guard let identifier = Int(term.dropFirst(prefix.count + 1)), identifier > 0 else { return [] }
        return items.filter { $0[keyPath: id] == identifier }
    }

    /// Keep spoken choices short; add catalog IDs only when title/year collide.
    static func choiceLabels<Item>(_ items: [Item], title: KeyPath<Item, String>, year: KeyPath<Item, Int>, id: KeyPath<Item, Int>) -> [String] {
        let labels = items.map { item in
            let year = item[keyPath: year]
            return item[keyPath: title] + (year > 0 ? " (\(year))" : "")
        }
        let counts = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
        return zip(items, labels).map { item, label in
            counts[label, default: 0] > 1 ? "\(label) [\(item[keyPath: id])]" : label
        }
    }

    /// Preserve requested order, skip invalid/duplicate IDs, and propagate failures.
    @MainActor
    static func resolve<Entity>(
        _ identifiers: [Int],
        lookup: (Int) async throws -> Entity?
    ) async throws -> [Entity] {
        var seen = Set<Int>()
        var entities: [Entity] = []
        for id in identifiers where id > 0 && seen.insert(id).inserted {
            try Task.checkCancellation()
            if let entity = try await lookup(id) { entities.append(entity) }
        }
        return entities
    }
}

enum MediaAddSelectionError: LocalizedError {
    case invalidChoice
    case missingAddOptions
    var errorDescription: String? {
        switch self {
        case .invalidChoice: "That selection is no longer available. Please search for the title again."
        case .missingAddOptions: "Set up a quality profile and root folder on your media server before adding a title."
        }
    }
}
