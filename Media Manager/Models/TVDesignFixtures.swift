#if DEBUG && os(tvOS)
import Foundation
import CoreGraphics
import ImageIO

/// Offline design review only. Installed before services start, and never in Release.
/// Run on a disposable simulator using --tv-design-fixtures.
enum TVDesignFixtures {
    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--tv-design-fixtures") else { return }
        URLProtocol.registerClass(TVDesignFixtureProtocol.self)
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for service in ["radarr", "sonarr", "sabnzb"] {
            arguments[service + "URL"] = "https://\(service).tv-design.invalid"
            // Synthetic credentials, migrated only into the disposable simulator's Keychain.
            arguments[service + "APIKey"] = "offline-design-fixture"
        }
        arguments["iCloudSyncEnabled"] = false
        arguments["unraidURL"] = ""
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}

final class TVDesignFixtureProtocol: URLProtocol {
    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        // Intercept every HTTP request in this explicit offline mode.
        ["http", "https"].contains(request.url?.scheme ?? "")
    }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func stopLoading() { }

    nonisolated override func startLoading() {
        guard let url = request.url else { return }
        let data: Data
        let mime: String
        let status: Int
        if url.path.hasPrefix("/poster/"), let poster = Self.poster(seed: Int(url.lastPathComponent) ?? 1) {
            data = poster
            mime = "image/png"
            status = 200
        } else if request.httpMethod == "GET" || request.httpMethod == nil {
            data = (try? JSONSerialization.data(withJSONObject: Self.payload(for: url), options: [.sortedKeys])) ?? Data("[]".utf8)
            mime = "application/json"
            status = 200
        } else {
            data = Data("{\"message\":\"Offline design review does not change server data.\"}".utf8)
            mime = "application/json"
            status = 403
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated private static func payload(for url: URL) -> Any {
        let isTV = url.host?.hasPrefix("sonarr") == true
        let path = url.path
        if url.host?.hasPrefix("sabnzb") == true {
            let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "mode" }?.value
            if mode == "history" { return ["history": ["slots": []]] }
            return ["queue": ["paused": false, "speed": "12.4 M", "kbpersec": "12400", "slots": [
                ["nzo_id": "sample-1", "filename": "The Last Observatory (2026) — 2160p", "cat": "movies", "status": "Downloading", "percentage": "64", "mb": "18000", "mbleft": "6480", "timeleft": "00:08:42"],
                ["nzo_id": "sample-2", "filename": "Beyond the Horizon — Season 2", "cat": "tv", "status": "Queued", "percentage": "0", "mb": "5200", "mbleft": "5200", "timeleft": "00:16:10"]
            ]]]
        }
        if path.hasSuffix("/qualityprofile") { return [["id": 1, "name": "HD • 1080p"], ["id": 2, "name": "Ultra HD • 4K"]] }
        if path.hasSuffix("/rootfolder") { return [["id": 1, "path": isTV ? "/media/television" : "/media/movies", "freeSpace": 2000000000000]] }
        if path.hasSuffix("/tag") { return [["id": 1, "label": "Family favourites"]] }
        if path.hasSuffix("/system/status") { return ["version": "Design review"] }
        if path.hasSuffix("/queue") || path.hasSuffix("/history") || path.contains("/wanted/") || path.hasSuffix("/blocklist") { return ["records": [], "totalRecords": 0, "page": 1, "pageSize": 20] }
        if path.hasSuffix("/movie") || path.hasSuffix("/series") || path.hasSuffix("/lookup") {
            return media(isTV: isTV)
        }
        return []
    }

    nonisolated private static func media(isTV: Bool) -> [[String: Any]] {
        let titles = isTV
            ? ["Beyond the Horizon", "The Midnight Garden", "Northbound", "A Thousand Small Adventures", "Signal Lost", "The Quiet City", "Blue Planet Diaries", "Parallel Lives", "After the Rain", "Coastal Stories", "Wild Skies", "The Long Way Home"]
            : ["The Last Observatory", "Across the Blue", "A Place Among the Stars", "The Midnight Train", "Wildwood", "Echoes of Tomorrow", "The Long Way Home", "One Summer in October", "Northern Lights", "A Different Kind of Hero", "The Silent Sea", "After the Storm"]
        return titles.enumerated().map { index, title in
            let id = index + 1
            var item: [String: Any] = [
                "id": id, "title": title, "year": 2026 - index % 5,
                "overview": "An unexpected discovery brings a group of strangers together on a remarkable journey. A story about curiosity, friendship, and finding a place to belong.",
                "monitored": index % 4 != 3, "qualityProfileId": 1,
                "status": isTV ? "continuing" : "released", "runtime": 118,
                "tmdbId": 900000 + id, "tvdbId": 800000 + id,
                "images": [["coverType": "poster", "url": "/poster/\(id)", "remoteUrl": "https://art.tv-design.invalid/poster/\(id)"]],
                "added": "2026-09-01T12:00:00Z", "path": "/media/\(title)", "tags": [1]
            ]
            if isTV {
                item["network"] = "Sample Network"
                item["statistics"] = ["seasonCount": 3, "episodeCount": 24, "episodeFileCount": 18, "totalEpisodeCount": 24, "sizeOnDisk": 24000000000, "percentOfEpisodes": 75]
            }
            return item
        }
    }

    /// Abstract, locally rendered sample artwork; no external images or requests.
    nonisolated private static func poster(seed: Int) -> Data? {
        let width = 240, height = 360
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: CGFloat(seed % 4) * 0.15 + 0.15, green: 0.12, blue: 0.45, alpha: 1), CGColor(red: 0.05, green: CGFloat(seed % 5) * 0.12 + 0.2, blue: 0.4, alpha: 1)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        context.fillEllipse(in: CGRect(x: 30 + seed * 4, y: 70, width: 170, height: 170))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 85))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
#endif
