import UIKit
import CryptoKit

/// Manages image caching with both memory (NSCache) and disk persistence
/// Provides significant bandwidth savings by avoiding redundant image downloads
actor ImageCacheManager {
    static let shared = ImageCacheManager()

    // MARK: - Memory Cache

    private let memoryCache = NSCache<NSString, UIImage>()

    // MARK: - Disk Cache

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxDiskCacheSize: Int64 = 100 * 1024 * 1024 // 100 MB
    private let maxDiskCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // MARK: - Request Deduplication

    private var inFlightRequests: [String: Task<UIImage?, Error>] = [:]

    // MARK: - Configuration Cache

    /// Cached configuration to avoid repeated UserDefaults lookups
    private var cachedRadarrURL: String?
    private var cachedRadarrAPIKey: String?
    private var cachedSonarrURL: String?
    private var cachedSonarrAPIKey: String?

    private init() {
        // Configure memory cache
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        // Setup disk cache directory
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("ImageCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load cached configuration inline (init is nonisolated in actors)
        cachedRadarrURL = UserDefaults.standard.string(forKey: "radarrURL")
        cachedRadarrAPIKey = CredentialStore.shared.string(for: .radarrAPIKey)
        cachedSonarrURL = UserDefaults.standard.string(forKey: "sonarrURL")
        cachedSonarrAPIKey = CredentialStore.shared.string(for: .sonarrAPIKey)

        // Clean up old cache files periodically
        Task.detached(priority: .background) { [weak self] in
            await self?.cleanupDiskCache()
        }
    }

    // MARK: - Configuration

    /// Load configuration values from UserDefaults
    private func loadConfiguration() {
        cachedRadarrURL = UserDefaults.standard.string(forKey: "radarrURL")
        cachedRadarrAPIKey = CredentialStore.shared.string(for: .radarrAPIKey)
        cachedSonarrURL = UserDefaults.standard.string(forKey: "sonarrURL")
        cachedSonarrAPIKey = CredentialStore.shared.string(for: .sonarrAPIKey)
    }

    /// Refresh cached configuration values from UserDefaults
    func refreshConfiguration() {
        loadConfiguration()
    }

    // MARK: - Cache Key Generation

    private func cacheKey(for url: URL) -> String {
        // Use SHA256 hash of URL for consistent, filesystem-safe keys
        let urlString = url.absoluteString
        let digest = SHA256.hash(data: Data(urlString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Memory Cache Operations

    private func getFromMemory(key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    private func setInMemory(key: String, image: UIImage) {
        let cost = Int(image.size.width * image.size.height * 4) // Approximate bytes
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    // MARK: - Disk Cache Operations

    private func diskCachePath(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key)
    }

    private func getFromDisk(key: String) -> UIImage? {
        let path = diskCachePath(for: key)

        guard fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else {
            return nil
        }

        // Update access time for LRU
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)

        return image
    }

    private func saveToDisk(key: String, data: Data) {
        let path = diskCachePath(for: key)
        try? data.write(to: path)
    }

    // MARK: - Public API

    /// Fetch image from cache or network
    /// Uses memory cache -> disk cache -> network fallback strategy
    func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        // 1. Check memory cache (fastest)
        if let cached = getFromMemory(key: key) {
            return cached
        }

        // 2. Check disk cache
        if let diskCached = getFromDisk(key: key) {
            // Promote to memory cache
            setInMemory(key: key, image: diskCached)
            return diskCached
        }

        // 3. Check for in-flight request (atomic check-and-set within actor)
        if let existingTask = inFlightRequests[key] {
            return try? await existingTask.value
        }

        // 4. Create new fetch task and register atomically
        let task = Task<UIImage?, Error> {
            try await fetchImage(from: url, key: key)
        }
        inFlightRequests[key] = task

        let result = try? await task.value
        inFlightRequests.removeValue(forKey: key)
        return result
    }

    /// Fetch image with authentication support for Radarr/Sonarr URLs
    private func fetchImage(from url: URL, key: String) async throws -> UIImage? {
        // Determine if this is an authenticated URL
        let isRadarrURL = matchesConfiguredServer(url, configuredURL: cachedRadarrURL)
        let isSonarrURL = matchesConfiguredServer(url, configuredURL: cachedSonarrURL)

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 15

        // Add API key for authenticated requests
        if isRadarrURL, let apiKey = cachedRadarrAPIKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        } else if isSonarrURL, let apiKey = cachedSonarrAPIKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }

        // Cache the image
        setInMemory(key: key, image: image)
        saveToDisk(key: key, data: data)

        return image
    }

    private func matchesConfiguredServer(_ url: URL, configuredURL: String?) -> Bool {
        guard let configuredURL,
              !configuredURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let server = URL(string: ConfigurationManager.normalizedServerURL(configuredURL)),
              let serverScheme = server.scheme?.lowercased(),
              let candidateScheme = url.scheme?.lowercased(),
              let serverHost = server.host?.lowercased(),
              let candidateHost = url.host?.lowercased(),
              serverScheme == candidateScheme,
              serverHost == candidateHost,
              server.port == url.port
        else {
            return false
        }

        let serverPath = server.path
        return serverPath.isEmpty || serverPath == "/" || url.path.hasPrefix(serverPath)
    }

    /// Prefetch images for a list of URLs (useful for scroll views)
    nonisolated func prefetch(urls: [URL]) {
        for url in urls {
            Task.detached(priority: .low) { [weak self] in
                _ = await self?.image(for: url)
            }
        }
    }

    // MARK: - Cache Management

    /// Clear all cached images
    func clearAll() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Clear only memory cache (useful for memory warnings)
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Clean up expired disk cache files
    private func cleanupDiskCache() async {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var filesToDelete: [URL] = []
        var totalSize: Int64 = 0
        var files: [(url: URL, date: Date, size: Int64)] = []

        let expirationDate = Date().addingTimeInterval(-maxDiskCacheAge)

        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = resourceValues.contentModificationDate,
                  let fileSize = resourceValues.fileSize else {
                continue
            }

            // Mark expired files for deletion
            if modDate < expirationDate {
                filesToDelete.append(fileURL)
            } else {
                files.append((url: fileURL, date: modDate, size: Int64(fileSize)))
                totalSize += Int64(fileSize)
            }
        }

        // Delete expired files
        for url in filesToDelete {
            try? fileManager.removeItem(at: url)
        }

        // If still over size limit, delete oldest files (LRU)
        if totalSize > maxDiskCacheSize {
            let sortedFiles = files.sorted { $0.date < $1.date }
            var currentSize = totalSize

            for file in sortedFiles {
                if currentSize <= maxDiskCacheSize * 80 / 100 { // Target 80% of max
                    break
                }
                try? fileManager.removeItem(at: file.url)
                currentSize -= file.size
            }
        }
    }
}
