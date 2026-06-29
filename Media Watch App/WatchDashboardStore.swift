import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchDashboardStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchDashboardSnapshot = .empty
    @Published private(set) var connectionStatus = "Waiting for iPhone"
    @Published private(set) var isRefreshing = false
    @Published var searchKind: WatchMediaKind = .movie
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [WatchMediaSearchResult] = []
    @Published private(set) var mediaActionStatus = ""
    @Published private(set) var isSearching = false
    @Published private(set) var addingResultId: String?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let snapshotDefaultsKey = "watchDashboardSnapshot"
    private var activationStarted = false

    override init() {
        super.init()
        loadCachedSnapshot()
    }

    func activate() {
        guard WCSession.isSupported(), !activationStarted else { return }
        activationStarted = true

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestRefresh() {
        send(command: WatchConnectivityCommand.refreshSnapshot)
    }

    func toggleDownloads() {
        send(command: WatchConnectivityCommand.toggleDownloads)
    }

    func searchMedia(kind: WatchMediaKind, query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            mediaActionStatus = "Say a movie or show title first."
            return
        }

        activate()
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            mediaActionStatus = "Open the iPhone app to search."
            return
        }

        let request = WatchMediaSearchRequest(id: UUID(), kind: kind, query: trimmedQuery)
        guard let payload = try? encoder.encode(request) else {
            mediaActionStatus = "Could not prepare search."
            return
        }

        searchKind = kind
        searchQuery = trimmedQuery
        searchResults = []
        mediaActionStatus = "Searching \(kind.title.lowercased())s..."
        isSearching = true

        let message: [String: Any] = [
            WatchConnectivityKey.command: WatchConnectivityCommand.searchMedia,
            WatchConnectivityKey.payload: payload
        ]

        WCSession.default.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.handleSearchReply(reply, request: request)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSearching = false
                self?.mediaActionStatus = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    func addMedia(_ result: WatchMediaSearchResult) {
        activate()
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            mediaActionStatus = "Open the iPhone app to add."
            return
        }

        let request = WatchMediaAddRequest(id: UUID(), result: result)
        guard let payload = try? encoder.encode(request) else {
            mediaActionStatus = "Could not prepare add."
            return
        }

        addingResultId = result.id
        mediaActionStatus = "Adding \(result.title)..."

        let message: [String: Any] = [
            WatchConnectivityKey.command: WatchConnectivityCommand.addMedia,
            WatchConnectivityKey.payload: payload
        ]

        WCSession.default.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.handleAddReply(reply, request: request)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.addingResultId = nil
                self?.mediaActionStatus = "Add failed: \(error.localizedDescription)"
            }
        }
    }

    private func send(command: String) {
        activate()
        guard WCSession.isSupported() else {
            connectionStatus = "Sync unavailable"
            return
        }

        isRefreshing = true
        let message = [WatchConnectivityKey.command: command]
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.connectionStatus = "Open iPhone app to sync"
                    self?.isRefreshing = false
                }
            }
        } else {
            session.transferUserInfo(message)
            connectionStatus = "Queued for iPhone"
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                isRefreshing = false
            }
        }
    }

    private func handleSearchReply(_ reply: [String: Any], request: WatchMediaSearchRequest) {
        isSearching = false

        guard let data = reply[WatchConnectivityKey.payload] as? Data,
              let response = try? decoder.decode(WatchMediaSearchResponse.self, from: data),
              response.requestId == request.id else {
            mediaActionStatus = "Search response was invalid."
            return
        }

        searchResults = response.results
        if let errorMessage = response.errorMessage {
            mediaActionStatus = errorMessage
        } else if response.results.isEmpty {
            mediaActionStatus = "No results for \(response.query)."
        } else {
            mediaActionStatus = "\(response.results.count) result\(response.results.count == 1 ? "" : "s") for \(response.query)."
        }
    }

    private func handleAddReply(_ reply: [String: Any], request: WatchMediaAddRequest) {
        addingResultId = nil

        guard let data = reply[WatchConnectivityKey.payload] as? Data,
              let response = try? decoder.decode(WatchMediaAddResponse.self, from: data),
              response.requestId == request.id else {
            mediaActionStatus = "Add response was invalid."
            return
        }

        mediaActionStatus = response.message
        if response.success {
            searchResults.removeAll { $0.id == response.resultId }
            requestRefresh()
        }
    }

    private func applySnapshotData(_ data: Data) {
        do {
            let decodedSnapshot = try decoder.decode(WatchDashboardSnapshot.self, from: data)
            snapshot = decodedSnapshot
            connectionStatus = "Synced \(relativeSyncText(for: decodedSnapshot.generatedAt))"
            isRefreshing = false
            UserDefaults.standard.set(data, forKey: snapshotDefaultsKey)
        } catch {
            connectionStatus = "Sync failed"
            isRefreshing = false
        }
    }

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: snapshotDefaultsKey),
              let decodedSnapshot = try? decoder.decode(WatchDashboardSnapshot.self, from: data) else {
            return
        }

        snapshot = decodedSnapshot
        connectionStatus = "Cached \(relativeSyncText(for: decodedSnapshot.generatedAt))"
    }

    private func relativeSyncText(for date: Date) -> String {
        guard date > .distantPast else { return "never" }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)

        if seconds < 60 {
            return "now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = hours / 24
        return "\(days)d ago"
    }
}

extension WatchDashboardStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.connectionStatus = error.localizedDescription
            } else if activationState == .activated {
                self.connectionStatus = session.isReachable ? "Connected" : self.connectionStatus
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.connectionStatus = session.isReachable ? "Connected" : self.connectionStatus
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchConnectivityKey.snapshot] as? Data else { return }
        Task { @MainActor in
            self.applySnapshotData(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchConnectivityKey.snapshot] as? Data else { return }
        Task { @MainActor in
            self.applySnapshotData(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchConnectivityKey.snapshot] as? Data else { return }
        Task { @MainActor in
            self.applySnapshotData(data)
        }
    }
}
