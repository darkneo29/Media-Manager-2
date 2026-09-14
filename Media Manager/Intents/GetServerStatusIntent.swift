import AppIntents

/// Intent to get Unraid server status
struct GetServerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Server Status"
    static var description = IntentDescription("Gets the current status of your Unraid server including CPU, memory, and storage.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let config = ConfigurationManager.shared

        guard config.isUnraidConfigured else {
            return .result(
                value: "Unraid is not configured",
                dialog: "Unraid is not configured. Please set up Unraid in the app settings."
            )
        }

        do {
            let overview = try await UnraidService.shared.fetchOverview()
            let summary = overview.spokenSummary

            return .result(
                value: summary,
                dialog: IntentDialog(stringLiteral: summary)
            )
        } catch {
            return .result(
                value: "Failed to get server status",
                dialog: "Failed to get server status: \(error.localizedDescription)"
            )
        }
    }
}
