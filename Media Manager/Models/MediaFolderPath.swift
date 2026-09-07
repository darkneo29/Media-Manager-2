import Foundation

/// Server paths may use Windows separators even when the client runs on iOS.
enum MediaFolderPath {
    nonisolated static func currentRoot(rootFolderPath: String?, path: String?) -> String {
        if let rootFolderPath, !rootFolderPath.isEmpty { return rootFolderPath }
        guard let path, let separator = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
            return ""
        }
        if separator == path.startIndex { return String(path[...separator]) }
        return String(path[..<separator])
    }

    /// Single-item PUT endpoints move to `path`, not just `rootFolderPath`.
    nonisolated static func applyingRoot(_ root: String?, to resource: [String: Any]) throws -> [String: Any] {
        guard let root, !root.isEmpty else { return resource }
        let path = resource["path"] as? String
        let oldRoot = currentRoot(rootFolderPath: resource["rootFolderPath"] as? String, path: path)
        let separators = CharacterSet(charactersIn: "/\\")
        guard root.trimmingCharacters(in: separators) != oldRoot.trimmingCharacters(in: separators) else {
            return resource
        }
        guard let path,
              let folder = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last,
              folder != ".", folder != ".." else {
            throw URLError(.cannotParseResponse)
        }

        let separator = root.contains("\\") ? "\\" : "/"
        let destination = root.hasSuffix(separator) ? root : root + separator
        var updated = resource
        updated["rootFolderPath"] = root
        updated["path"] = destination + folder
        return updated
    }
}
