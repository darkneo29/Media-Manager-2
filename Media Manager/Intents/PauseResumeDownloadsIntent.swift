import AppIntents
import Foundation

/// Enum for download queue action
enum DownloadQueueAction: String, AppEnum {
    case pause
    case resume
    case toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Download Action"

    static var caseDisplayRepresentations: [DownloadQueueAction: DisplayRepresentation] = [
        .pause: "Pause",
        .resume: "Resume",
        .toggle: "Toggle"
    ]
}

/// Intent to pause or resume the download queue
struct PauseResumeDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause or Resume Downloads"
    static var description = IntentDescription("Pauses or resumes your download queue in SabNZB.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Action", default: .toggle)
    var action: DownloadQueueAction

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
            // First get current queue state if toggling
            let shouldPause: Bool
            if action == .toggle {
                let queue = try await SabNZBService.shared.fetchQueue()
                shouldPause = !queue.paused
            } else {
                shouldPause = action == .pause
            }

            if shouldPause {
                try await SabNZBService.shared.pauseQueue()
                return .result(
                    value: "Downloads paused",
                    dialog: "Download queue has been paused."
                )
            } else {
                try await SabNZBService.shared.resumeQueue()
                return .result(
                    value: "Downloads resumed",
                    dialog: "Download queue has been resumed."
                )
            }
        } catch {
            return .result(
                value: "Failed to \(action.rawValue) downloads",
                dialog: "Failed to \(action.rawValue) downloads: \(error.localizedDescription)"
            )
        }
    }
}
