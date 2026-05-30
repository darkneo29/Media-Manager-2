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
            let (system, array, containers, _) = try await UnraidService.shared.fetchAllData()

            // Format uptime
            let hours = system.uptime / 3600
            let days = hours / 24
            let remainingHours = hours % 24
            let uptimeString = days > 0 ? "\(days)d \(remainingHours)h" : "\(hours)h"

            // Format memory
            let memoryUsedGB = Double(system.memory.used) / (1024 * 1024 * 1024)
            let memoryTotalGB = Double(system.memory.total) / (1024 * 1024 * 1024)
            let memoryPercent = system.memory.usagePercentage

            // Format storage
            let storageUsedTB = Double(array.capacity.used) / (1000 * 1000 * 1000 * 1000)
            let storageTotalTB = Double(array.capacity.total) / (1000 * 1000 * 1000 * 1000)
            let storagePercent = array.capacity.usagePercentage

            // Count running containers
            let runningContainers = containers.filter { $0.state == .running }.count
            let totalContainers = containers.count

            let summary = """
            \(system.hostname) is online. \
            Uptime: \(uptimeString). \
            CPU: \(Int(system.cpu.usage))%. \
            Memory: \(String(format: "%.1f", memoryUsedGB))/\(String(format: "%.1f", memoryTotalGB)) GB (\(Int(memoryPercent))%). \
            Storage: \(String(format: "%.1f", storageUsedTB))/\(String(format: "%.1f", storageTotalTB)) TB (\(Int(storagePercent))%). \
            Containers: \(runningContainers)/\(totalContainers) running.
            """

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
