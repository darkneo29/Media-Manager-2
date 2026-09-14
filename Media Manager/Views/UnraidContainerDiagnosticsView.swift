import SwiftUI

struct UnraidContainerDiagnosticsView: View {
    let container: DockerContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var configuration = ConfigurationManager.shared
    @State private var logs = UnraidSection<UnraidContainerLogs>()
    @State private var stats: UnraidContainerStats?
    @State private var statsError: String?
    @State private var statsTime: Date?
    @State private var refreshing = false
    @State private var refreshID = UUID()

    private struct TaskKey: Hashable {
        let active: Bool
        let url: String
        let key: String
        let refresh: UUID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text(container.image).font(AppTypography.caption1()).foregroundColor(ColorPalette.textMutedDark)
                    Text(container.status)
                    Group {
                        if let stats {
                            Text("CPU: \(stats.cpuPercent, specifier: "%.1f")%")
                            Text("Memory: \(stats.memUsage) (\(stats.memPercent, specifier: "%.1f")%)")
                            Text("Network I/O: \(stats.netIO)")
                            Text("Block I/O: \(stats.blockIO)")
                        } else if statsError == nil { ProgressView("Waiting for resource metrics…") }
                    }
                    UnraidSectionMessage(title: "Resource metrics", error: statsError, updatedAt: statsTime)
                    Text("Recent logs").font(AppTypography.headline())
                    Text("Most recent 200 lines. Refresh to retrieve new logs.")
                        .font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
                    if refreshing && logs.value == nil { ProgressView() }
                    UnraidSectionMessage(title: "Logs", error: logs.error, updatedAt: logs.updatedAt)
                    if let value = logs.value {
                        if value.lines.isEmpty { Text("No log lines returned.") }
                        ForEach(Array(value.lines.prefix(200).enumerated()), id: \.offset) { _, line in
                            Text("\(line.timestamp)  \(String(line.message.prefix(4096)))")
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.lg)
            }
            .background(ColorPalette.backgroundDark)
            .navigationTitle(container.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { refreshID = UUID() }.disabled(refreshing)
                }
            }
            .task(id: TaskKey(active: scenePhase == .active, url: configuration.unraidURL,
                              key: configuration.unraidAPIKey, refresh: refreshID)) {
                guard scenePhase == .active else { return }
                async let logsWork: Void = loadLogs()
                async let statsWork: Void = receiveStats()
                _ = await (logsWork, statsWork)
            }
        }
    }

    private func loadLogs() async {
        refreshing = true
        defer { refreshing = false }
        do {
            let result = try await UnraidService.shared.fetchContainerLogs(id: container.id, forceRefresh: true)
            guard !Task.isCancelled else { return }
            logs = result
        } catch {
            guard !Task.isCancelled else { return }
            logs.error = error.localizedDescription
        }
    }

    private func receiveStats() async {
        statsError = nil
        for attempt in 0..<3 {
            do {
                try await UnraidService.shared.watchContainerStats(id: container.id) { value in
                    stats = value
                    statsTime = Date()
                    statsError = nil
                }
                guard !Task.isCancelled else { return }
                statsError = "The server ended the metrics stream. Refresh to reconnect."
                return
            } catch {
                guard !Task.isCancelled else { return }
                statsError = error.localizedDescription
                guard attempt < 2, UnraidService.shouldRetryRead(error) else { return }
                do { try await Task.sleep(for: .seconds(pow(2, Double(attempt + 1)))) }
                catch { return }
            }
        }
    }
}
