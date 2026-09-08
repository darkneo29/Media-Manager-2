import Foundation
import Combine
import WatchConnectivity
import WatchKit

@MainActor
final class WatchDashboardStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchDashboardSnapshot = .empty
    @Published private(set) var connectionStatus = "Waiting for iPhone"
    @Published private(set) var isRefreshing = false
    @Published var searchKind: WatchMediaKind = .movie {
        didSet {
            if oldValue != searchKind { searchResults = []; mediaActionStatus = "" }
        }
    }
    @Published private(set) var addedResultIds: Set<String> = []
    @Published private(set) var isControllingDownloads = false
    @Published private(set) var downloadActionStatus = ""
    private var pendingRefresh = false
    private var activeSearchId: UUID?
    private var activeAddId: UUID?
    private var controlId: UUID?

    var hasSnapshot: Bool { snapshot.generatedAt > .distantPast }
    func isAdded(_ result: WatchMediaSearchResult) -> Bool {
        result.isInLibrary == true || addedResultIds.contains(result.id)
    }
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [WatchMediaSearchResult] = []
    @Published private(set) var mediaActionStatus = ""
    @Published private(set) var isSearching = false
    @Published private(set) var addingResultId: String?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let snapshotDefaultsKey = "watchDashboardSnapshot"
    private var activationStarted = false
    private var refreshRequestGeneration = 0

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

    func requestRefresh(queueWhenUnreachable: Bool = true) {
        guard !isRefreshing else { return }
        send(command: queueWhenUnreachable ? WatchConnectivityCommand.refreshSnapshot : WatchConnectivityCommand.refreshDownloads, queueWhenUnreachable: queueWhenUnreachable)
    }

    func toggleDownloads() {
        guard !isControllingDownloads, snapshot.downloads.isConfigured,
              snapshot.downloads.errorMessage == nil else { return }
        activate()
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            downloadActionStatus = "Open the iPhone app to control downloads."
            return
        }
        let id = UUID()
        controlId = id
        isControllingDownloads = true
        downloadActionStatus = ""
        WCSession.default.sendMessage([
            WatchConnectivityKey.command: WatchConnectivityCommand.setDownloadsPaused,
            WatchConnectivityKey.paused: !snapshot.downloads.isPaused
        ]) { [weak self] reply in
            Task { @MainActor in
                guard let self, self.controlId == id else { return }
                self.controlId = nil
                self.isControllingDownloads = false
                self.downloadActionStatus = reply[WatchConnectivityKey.error] as? String ??
                    (reply[WatchConnectivityKey.success] as? Bool == true ? "Queue updated." : "Could not confirm the change. Update the iPhone app and refresh.")
                self.requestRefresh()
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.controlId == id else { return }
                self.controlId = nil
                self.isControllingDownloads = false
                self.downloadActionStatus = "Could not confirm the change. Refresh to check the queue."
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.controlId == id else { return }
            self.controlId = nil
            self.isControllingDownloads = false
            self.downloadActionStatus = "No reply. Refresh to check the queue."
        }
    }

    func searchMedia(kind: WatchMediaKind, query: String) {
        guard !isSearching, addingResultId == nil else { return }

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
        activeSearchId = request.id
        scheduleMediaTimeout(id: request.id, isAdd: false)

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
                guard self?.activeSearchId == request.id else { return }
                self?.activeSearchId = nil
                self?.isSearching = false
                self?.mediaActionStatus = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    func addMedia(_ result: WatchMediaSearchResult) {
        guard addingResultId == nil, !isSearching, !isAdded(result) else { return }

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
        activeAddId = request.id
        scheduleMediaTimeout(id: request.id, isAdd: true)
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
                guard self?.activeAddId == request.id else { return }
                self?.activeAddId = nil
                self?.addingResultId = nil
                self?.mediaActionStatus = "Could not confirm the add. Check your iPhone library before retrying."
            }
        }
    }

    private func send(command: String, queueWhenUnreachable: Bool = true) {
        activate()
        guard WCSession.isSupported() else {
            connectionStatus = "Sync unavailable"
            return
        }

        guard WCSession.default.activationState == .activated else {
            pendingRefresh = true
            connectionStatus = "Connecting to iPhone…"
            return
        }
        refreshRequestGeneration += 1
        let requestGeneration = refreshRequestGeneration
        isRefreshing = true
        let message = [WatchConnectivityKey.command: command]
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    guard self?.refreshRequestGeneration == requestGeneration else { return }
                    self?.connectionStatus = "Open iPhone app to sync"
                    self?.isRefreshing = false
                }
            }
            stopRefreshIndicatorAfterTimeout(for: requestGeneration)
        } else if queueWhenUnreachable {
            if !session.outstandingUserInfoTransfers.contains(where: {
                $0.userInfo[WatchConnectivityKey.command] as? String == command
            }) { session.transferUserInfo(message) }
            connectionStatus = "Queued for iPhone"
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard refreshRequestGeneration == requestGeneration else { return }
                isRefreshing = false
            }
        } else {
            connectionStatus = "Open iPhone app to control"
            isRefreshing = false
        }
    }

    private func stopRefreshIndicatorAfterTimeout(for requestGeneration: Int) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self,
                  self.refreshRequestGeneration == requestGeneration,
                  self.isRefreshing else { return }
            self.isRefreshing = false
            self.connectionStatus = "No reply. Open the iPhone app to sync."
        }
    }

    private func handleSearchReply(_ reply: [String: Any], request: WatchMediaSearchRequest) {
        guard activeSearchId == request.id else { return }
        activeSearchId = nil
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
        guard activeAddId == request.id else { return }
        activeAddId = nil
        addingResultId = nil

        guard let data = reply[WatchConnectivityKey.payload] as? Data,
              let response = try? decoder.decode(WatchMediaAddResponse.self, from: data),
              response.requestId == request.id, response.resultId == request.result.id else {
            mediaActionStatus = "Add response was invalid."
            return
        }

        mediaActionStatus = response.message
        if response.success {
            addedResultIds.insert(response.resultId)
            WKInterfaceDevice.current().play(.success)
            requestRefresh()
        }
    }

    private func scheduleMediaTimeout(id: UUID, isAdd: Bool) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self else { return }
            if isAdd {
                guard self.activeAddId == id else { return }
                self.activeAddId = nil
                self.addingResultId = nil
                self.mediaActionStatus = "No reply. Check your iPhone library before trying to add again."
            } else {
                guard self.activeSearchId == id else { return }
                self.activeSearchId = nil
                self.isSearching = false
                self.mediaActionStatus = "Search timed out. Open the iPhone app and try again."
            }
        }
    }

    private func applySnapshotData(_ data: Data) {
        do {
            let decodedSnapshot = try decoder.decode(WatchDashboardSnapshot.self, from: data)
            guard decodedSnapshot.generatedAt >= snapshot.generatedAt else { return }
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
                if let data = session.receivedApplicationContext[WatchConnectivityKey.snapshot] as? Data {
                    self.applySnapshotData(data)
                }
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.requestRefresh()
                }
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.connectionStatus = session.isReachable ? "Connected" : "iPhone unavailable • showing saved data"
            if session.isReachable { self.requestRefresh() }
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
