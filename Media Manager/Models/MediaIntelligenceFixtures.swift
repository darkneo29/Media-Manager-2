#if DEBUG && os(iOS)
import Foundation

/// Read-only fixture server for system App Intents and screen-annotation tests.
enum MediaIntelligenceFixtures {
    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--media-intelligence-fixtures") else { return }
        URLProtocol.registerClass(MediaIntelligenceFixtureProtocol.self)
        var defaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults["radarrURL"] = "https://media-intelligence-fixture.invalid"
        defaults["sonarrURL"] = ""
        defaults["sabnzbURL"] = ""
        defaults["unraidURL"] = ""
        defaults["iCloudSyncEnabled"] = false
        UserDefaults.standard.setVolatileDomain(defaults, forName: UserDefaults.argumentDomain)
        try? CredentialStore.shared.set("synthetic-fixture-key", for: .radarrAPIKey)
    }
}

private final class MediaIntelligenceFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "media-intelligence-fixture.invalid"
    }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func stopLoading() {}
    nonisolated override func startLoading() {
        guard request.httpMethod == "GET", let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let movie: [String: Any] = ["id": 42, "tmdbId": 800, "title": "The Lunar Garden", "year": 2026,
                                  "overview": "Botanists grow a garden on the moon during a space expedition.",
                                  "runtime": 90, "monitored": true, "status": "released", "images": []]
        let rows: [[String: Any]]
        if url.path == "/api/v3/movie" { rows = [movie] }
        else if url.path == "/api/v3/movie/lookup" {
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value ?? ""
            rows = term == "tmdb:800" || term.localizedCaseInsensitiveContains("lunar") ? [movie] : []
        } else { rows = [] }
        do {
            let data = try JSONSerialization.data(withJSONObject: rows)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
#endif
