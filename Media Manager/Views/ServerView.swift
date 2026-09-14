import SwiftUI
import Combine

struct ServerView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var configuration = ConfigurationManager.shared

    /// When true, the view is embedded in another NavigationStack (e.g., from Dashboard)
    var isEmbedded: Bool = false

    @AppStorage("unraidShowMediaStackFirst") private var showMediaStackFirst: Bool = true

    @State private var snapshot: UnraidDetailSnapshot?
    @State private var selectedContainer: DockerContainer?
    @State private var commandNotice: String?
    @State private var systemInfo: UnraidSystemInfo?
    @State private var array: UnraidArray?
    @State private var containers: [DockerContainer] = []
    @State private var vms: [VmDomain] = []
    @State private var restartingContainerIds: Set<String> = []  // Track containers being restarted
    @State private var restartingVmIds: Set<String> = []  // Track VMs being restarted

    @State private var isLoading = true
    @State private var error: String?
    @State private var commandError: String?
    @State private var lastRefresh = Date()

    // Cached computed properties to avoid recalculating on every render
    @State private var cachedMediaStackContainers: [DockerContainer] = []
    @State private var cachedOtherContainers: [DockerContainer] = []
    @State private var cachedRunningCount: Int = 0

    // Task tracking for proper cancellation
    @State private var loadGeneration = UUID()
    @State private var containerOperationTasks: [String: Task<Void, Never>] = [:]
    @State private var vmOperationTasks: [String: Task<Void, Never>] = [:]

    // Visibility tracking for smart refresh
    @State private var isViewVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isEmbedded {
            // When embedded in another NavigationStack, don't create a new one
            serverContent
        } else {
            // When used as a standalone tab, wrap in NavigationStack
            NavigationStack {
                serverContent
            }
        }
    }

    @ViewBuilder
    private var serverContent: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            if !isConfigured {
                notConfiguredView
            } else if isLoading && snapshot == nil {
                loadingView
            } else if let error = error, snapshot == nil {
                errorView(error)
            } else {
                mainContent
            }
        }
        .alert("Unraid command failed", isPresented: Binding(
            get: { commandError != nil },
            set: { if !$0 { commandError = nil } }
        )) {
            Button("OK", role: .cancel) { commandError = nil }
        } message: {
            Text(commandError ?? "")
        }
        .sheet(item: $selectedContainer) { container in
            UnraidContainerDiagnosticsView(container: container)
        }
        .alert("VM command accepted", isPresented: Binding(
            get: { commandNotice != nil }, set: { if !$0 { commandNotice = nil } }
        )) { Button("OK", role: .cancel) { commandNotice = nil } }
        message: { Text(commandNotice ?? "") }
        .navigationTitle("Server")
        .navBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isConfigured {
                    Button(action: {
                        Task { await refreshData(forceRefresh: true) }
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.secondary))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(ColorPalette.secondary)
                        }
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("unraid.refresh")
                }
            }
        }
        .task(id: [configuration.unraidURL, configuration.unraidAPIKey]) {
            selectedContainer = nil
            snapshot = nil
            systemInfo = nil
            array = nil
            containers = []
            vms = []
            updateCachedContainers()
            if isConfigured { await loadData() }
        }
        .task(id: isViewVisible && scenePhase == .active) {
            // Only run refresh timer when view is visible and app is active
            guard isViewVisible && scenePhase == .active && isConfigured else { return }

            // Start periodic refresh
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Fast data only; section caches retain slow data.
                guard !Task.isCancelled && isViewVisible && scenePhase == .active && !isLoading else { continue }
                await refreshData()
            }
        }
        .onAppear {
            isViewVisible = true
        }
        .onDisappear {
            isViewVisible = false
            // User-issued commands must finish even when navigating away,
            // especially a restart's stop/start compatibility sequence.
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Kick an immediate refresh when returning to foreground while visible.
            if newPhase == .active && isViewVisible && isConfigured {
                Task { await refreshData() }
            }
        }
    }

    // MARK: - Configuration Check

    private var isConfigured: Bool {
        configuration.isUnraidConfigured
    }

    /// Check if we're on tvOS
    private var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Views

    private var notConfiguredView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundColor(ColorPalette.textMutedDark)

            Text("Unraid Not Configured")
                .font(AppTypography.title2())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text("Go to Settings to add your Unraid server URL and API key.")
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
        }
    }

    private var loadingView: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.secondary))
                .scaleEffect(1.2)

            Text("Connecting to server...")
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textSecondaryDark)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorPalette.error)

            Text("Connection Error")
                .font(AppTypography.title3())
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text(message)
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textSecondaryDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            Button(action: {
                Task { await loadData() }
            }) {
                Text("Try Again")
                    .font(AppTypography.body(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(ColorPalette.primary)
                    .cornerRadius(AppRadius.md)
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: isTVOS ? TVSizing.sectionSpacing : AppSpacing.lg) {
                if let systemInfo {
                    SystemStatusCard(systemInfo: systemInfo, arrayState: array?.state ?? .unknown)
                } else if let metrics = snapshot?.overview.metrics.value, snapshot?.overview.metrics.error == nil {
                    UnraidMetricsCard(metrics: metrics)
                }
                UnraidSectionMessage(title: "System", error: snapshot?.overview.system.error, updatedAt: snapshot?.overview.system.updatedAt)
                UnraidSectionMessage(title: "Metrics", error: snapshot?.overview.metrics.error, updatedAt: snapshot?.overview.metrics.updatedAt)
                if let array { StorageOverviewCard(array: array, diskInventory: snapshot?.disks.error == nil ? snapshot?.disks.value?.disks : nil) }
                UnraidSectionMessage(title: "Storage", error: snapshot?.overview.storage.error, updatedAt: snapshot?.overview.storage.updatedAt)
                if let disks = snapshot?.disks.value?.disks, !disks.isEmpty { disksSection(disks: disks) }
                UnraidSectionMessage(title: "Disks", error: snapshot?.disks.error, updatedAt: snapshot?.disks.updatedAt)
                if let parity = snapshot?.parity.value { UnraidParityCard(parity: parity) }
                UnraidSectionMessage(title: "Parity", error: snapshot?.parity.error, updatedAt: snapshot?.parity.updatedAt)
                vmsSection
                UnraidSectionMessage(title: "Virtual machines", error: snapshot?.vms.error, updatedAt: snapshot?.vms.updatedAt)
                if vms.isEmpty && snapshot?.vms.error == nil { Text("No virtual machines").foregroundColor(ColorPalette.textMutedDark) }
                dockerSection
                UnraidSectionMessage(title: "Containers", error: snapshot?.containers.error, updatedAt: snapshot?.containers.updatedAt)
                if containers.isEmpty && snapshot?.containers.error == nil { Text("No containers").foregroundColor(ColorPalette.textMutedDark) }
                if let caps = snapshot?.capabilities { UnraidAccessSummary(capabilities: caps) }

                // Last Refresh Info
                HStack {
                    Spacer()
                    Text("Last updated: \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(isTVOS ? AppTypography.body() : AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }
                .padding(.top, AppSpacing.sm)
            }
            .padding(.horizontal, isTVOS ? TVSizing.contentPadding : AppSpacing.md)
            .padding(.top, isTVOS ? TVSizing.contentPadding : AppSpacing.sm)
            .padding(.bottom, isTVOS ? TVSizing.contentPadding : AppSpacing.xl)
        }
        .refreshable {
            await refreshData(forceRefresh: true)
        }
    }

    // MARK: - Disks Section

    /// Adaptive grid columns: 6 on tvOS, 4 on iPad, 2 on iPhone
    private var diskGridColumns: [GridItem] {
        #if os(tvOS)
        let columnCount = 6
        return Array(repeating: GridItem(.flexible(), spacing: TVSizing.gridSpacing), count: columnCount)
        #else
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: columnCount)
        #endif
    }

    private func disksSection(disks: [UnraidDisk]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionTitle(text: "Disks")

            LazyVGrid(columns: diskGridColumns, spacing: AppSpacing.sm) {
                ForEach(disks) { disk in
                    CompactDiskCard(disk: disk)
                }
            }
        }
    }

    // MARK: - Docker Section

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Section Header
            HStack {
                SectionTitle(text: "Docker Containers")

                Spacer()

                Text(snapshot?.containers.error == nil ? "\(cachedRunningCount)/\(containers.count) running" : "Status unavailable")
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            // Split containers into groups
            if showMediaStackFirst {
                // Media Stack First
                if !cachedMediaStackContainers.isEmpty {
                    ContainerGroupCard(
                        title: "MEDIA STACK",
                        containers: cachedMediaStackContainers,
                        restartingContainerIds: restartingContainerIds,
                        busyContainerIds: Set(containerOperationTasks.keys),
                        capabilities: snapshot?.capabilities ?? UnraidCapabilities(),
                        onInspect: { selectedContainer = $0 },
                        onStart: startContainer,
                        onStop: stopContainer,
                        onRestart: restartContainer
                    )
                }

                if !cachedOtherContainers.isEmpty {
                    ContainerGroupCard(
                        title: "OTHER CONTAINERS",
                        containers: cachedOtherContainers,
                        restartingContainerIds: restartingContainerIds,
                        busyContainerIds: Set(containerOperationTasks.keys),
                        capabilities: snapshot?.capabilities ?? UnraidCapabilities(),
                        onInspect: { selectedContainer = $0 },
                        onStart: startContainer,
                        onStop: stopContainer,
                        onRestart: restartContainer
                    )
                }
            } else {
                // All containers in one group
                VStack(spacing: 1) {
                    ForEach(containers) { container in
                        DockerContainerCard(
                            container: container,
                            isRestarting: restartingContainerIds.contains(container.id),
                            isBusy: containerOperationTasks[container.id] != nil,
                            capabilities: snapshot?.capabilities ?? UnraidCapabilities(),
                            onInspect: { selectedContainer = container },
                            onStart: { startContainer(container) },
                            onStop: { stopContainer(container) },
                            onRestart: { restartContainer(container) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - VMs Section

    private var vmsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            VMGroupCard(
                vms: vms,
                stateAvailable: snapshot?.vms.error == nil,
                restartingVmIds: restartingVmIds,
                busyVmIds: Set(vmOperationTasks.keys),
                capabilities: snapshot?.capabilities ?? UnraidCapabilities(),
                onStart: startVm,
                onStop: stopVm,
                onRestart: restartVm,
                onForceStop: forceStopVm
            )
        }
    }

    // MARK: - Container Helpers

    /// Updates cached container lists when containers change
    private func updateCachedContainers() {
        cachedMediaStackContainers = containers.filter { $0.isMediaStack }.sorted { $0.displayName < $1.displayName }
        cachedOtherContainers = containers.filter { !$0.isMediaStack }.sorted { $0.displayName < $1.displayName }
        cachedRunningCount = containers.filter { $0.state.isRunning }.count
    }

    // MARK: - Container Actions

    private func startContainer(_ container: DockerContainer) {
        runContainerCommand(container) {
            if container.state == .paused { try await UnraidService.shared.resumeContainer(id: container.id) }
            else { try await UnraidService.shared.startContainer(id: container.id) }
        }
    }

    private func stopContainer(_ container: DockerContainer) {
        runContainerCommand(container) { try await UnraidService.shared.stopContainer(id: container.id) }
    }

    private func restartContainer(_ container: DockerContainer) {
        runContainerCommand(container, restarting: true) { try await UnraidService.shared.restartContainer(id: container.id) }
    }

    private func runContainerCommand(_ container: DockerContainer, restarting: Bool = false, action: @escaping () async throws -> Void) {
        guard containerOperationTasks[container.id] == nil else { return }
        if restarting { restartingContainerIds.insert(container.id) }
        containerOperationTasks[container.id] = Task {
            defer {
                restartingContainerIds.remove(container.id)
                containerOperationTasks.removeValue(forKey: container.id)
            }
            do { try await action() }
            catch { if !Task.isCancelled { commandError = "\(container.displayName): \(error.localizedDescription)" } }
            if isViewVisible && !Task.isCancelled { await refreshData() }
        }
    }

    // MARK: - VM Actions

    private func startVm(_ vm: VmDomain) {
        runVmCommand(vm) {
            if vm.state == .paused { return try await UnraidService.shared.resumeVm(id: vm.id) }
            else { return try await UnraidService.shared.startVm(id: vm.id) }
        }
    }
    private func stopVm(_ vm: VmDomain) {
        runVmCommand(vm) { try await UnraidService.shared.stopVm(id: vm.id) }
    }
    private func restartVm(_ vm: VmDomain) {
        runVmCommand(vm, restarting: true) { try await UnraidService.shared.restartVm(id: vm.id) }
    }
    private func forceStopVm(_ vm: VmDomain) {
        runVmCommand(vm) { try await UnraidService.shared.forceStopVm(id: vm.id) }
    }

    private func runVmCommand(_ vm: VmDomain, restarting: Bool = false, action: @escaping () async throws -> UnraidVMCommandResult) {
        guard vmOperationTasks[vm.id] == nil else { return }
        if restarting { restartingVmIds.insert(vm.id) }
        vmOperationTasks[vm.id] = Task {
            defer {
                restartingVmIds.remove(vm.id)
                vmOperationTasks.removeValue(forKey: vm.id)
            }
            do {
                if case .unverified(let message) = try await action() { commandNotice = "\(vm.displayName): \(message)" }
            }
            catch { if !Task.isCancelled { commandError = "\(vm.displayName): \(error.localizedDescription)" } }
            if isViewVisible && !Task.isCancelled { await refreshData() }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        await refreshData()
    }

    private func refreshData(forceRefresh: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        defer { if loadGeneration == generation { isLoading = false } }
        do {
            let data = try await UnraidService.shared.fetchDetails(forceRefresh: forceRefresh)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            snapshot = data
            systemInfo = data.overview.system.value
            array = data.overview.storage.value
            containers = data.containers.value ?? []
            vms = data.vms.value ?? []
            updateCachedContainers()
            lastRefresh = Date()
            error = nil
        } catch is CancellationError {
            // A new server or newer request superseded this response.
        } catch {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }

}

#Preview {
    ServerView()
        .preferredColorScheme(.dark)
}
