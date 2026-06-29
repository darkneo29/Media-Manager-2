import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchDashboardStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchDashboardSnapshot = .empty
    @Published private(set) var connectionStatus = "Waiting for iPhone"
    @Published private(set) var isRefreshing = false

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

enum WatchConnectivityKey {
    nonisolated static let command = "command"
    nonisolated static let snapshot = "snapshot"
}

enum WatchConnectivityCommand {
    nonisolated static let refreshSnapshot = "refreshSnapshot"
    nonisolated static let toggleDownloads = "toggleDownloads"
}
