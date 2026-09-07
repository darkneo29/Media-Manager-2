import Foundation

enum ServerImageURL {
    nonisolated static func resolve(_ path: String, serverURL: String) -> URL? {
        if let absolute = URL(string: path),
           let scheme = absolute.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return absolute
        }
        guard !path.isEmpty,
              var server = URLComponents(string: ConfigurationManager.normalizedServerURL(serverURL)),
              let scheme = server.scheme?.lowercased(), ["http", "https"].contains(scheme),
              server.host != nil,
              let image = URLComponents(string: path), image.scheme == nil, image.host == nil else {
            return nil
        }
        let basePath = server.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let imagePath = image.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Arr can return a path which already includes the reverse proxy URL base.
        if basePath.isEmpty || imagePath == basePath || imagePath.hasPrefix(basePath + "/") {
            server.percentEncodedPath = "/" + imagePath
        } else {
            server.percentEncodedPath = "/" + basePath + "/" + imagePath
        }
        server.percentEncodedQuery = image.percentEncodedQuery
        server.fragment = nil
        return server.url
    }

    nonisolated static func matchesServer(_ url: URL, serverURL: String?) -> Bool {
        guard let serverURL, !serverURL.isEmpty,
              let server = URL(string: ConfigurationManager.normalizedServerURL(serverURL)),
              let scheme = server.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.scheme?.lowercased() == scheme,
              let host = server.host?.lowercased(), url.host?.lowercased() == host,
              (server.port ?? (scheme == "https" ? 443 : 80)) == (url.port ?? (scheme == "https" ? 443 : 80)) else {
            return false
        }
        let base = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.isEmpty || path == base || path.hasPrefix(base + "/")
    }
}
