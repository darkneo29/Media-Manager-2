import AppIntents
import Foundation

/// Intent to get the current download queue status from SabNZB
struct GetDownloadQueueStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Download Queue Status"
    static var description = IntentDescription("Gets the current status of your download queue including active downloads, speed, and progress.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isSabNZBConfigured else {
            return .result(
                value: "SabNZB is not configured",
                dialog: "SabNZB is not configured. Please set up SabNZB in the app settings."
            )
        }

        do {
            let queue = try await SabNZBService.shared.fetchQueue()

            if queue.downloads.isEmpty {
                let status = queue.paused ? "paused with no downloads" : "empty"
                return .result(
                    value: "Queue is \(status)",
                    dialog: "Your download queue is \(status)."
                )
            }

            let activeCount = queue.downloads.filter { $0.status == .downloading }.count
            let pausedCount = queue.downloads.filter { $0.status == .paused }.count
            let totalCount = queue.downloads.count

            let speedMBps = Double(queue.speed) / (1024 * 1024)
            let speedFormatted = String(format: "%.1f MB/s", speedMBps)

            var summary = "\(totalCount) download\(totalCount == 1 ? "" : "s")"
            if activeCount > 0 {
                summary += ", \(activeCount) active at \(speedFormatted)"
            }
            if pausedCount > 0 {
                summary += ", \(pausedCount) paused"
            }
            if queue.paused {
                summary += " (Queue paused)"
            }

            // Get first download details
            if let first = queue.downloads.first {
                let progress = Int(first.progress)
                summary += ". Current: \(first.name) (\(progress)%)"
            }

            return .result(
                value: summary,
                dialog: IntentDialog(stringLiteral: summary)
            )
        } catch {
            return .result(
                value: "Failed to get queue status",
                dialog: "Failed to get download queue status: \(error.localizedDescription)"
            )
        }
    }
}
