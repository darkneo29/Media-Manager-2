import SwiftUI

struct ServerHealthWidget: View {
    @ObservedObject private var configuration = ConfigurationManager.shared

    @State private var systemInfo: UnraidSystemInfo?
    @State private var array: UnraidArray?
    @State private var runningContainers: Int = 0
    @State private var totalContainers: Int = 0
    @State private var isLoading = true
    @State private var hasError = false
    @State private var retryCount = 0
    @State private var isVisible = false

    /// Whether to show the section header (title + View All)
    var showHeader: Bool = false
    var onTap: (() -> Void)?

    private let maxRetries = 3
    private let retryDelaySeconds: UInt64 = 10

    var isConfigured: Bool {
        configuration.isUnraidConfigured
    }

    var body: some View {
        // Only show if configured (show even with error for recovery)
        if isConfigured {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Optional section header
                if showHeader {
                    HStack {
                        Text("Server Health")
                            .font(AppTypography.title3())
                            .foregroundColor(ColorPalette.textPrimaryDark)

                        Spacer()

                        Button(action: { onTap?() }) {
                            Text("View All")
                                .font(AppTypography.caption1())
                                .foregroundColor(ColorPalette.secondary)
                        }
                    }
                }

                // Widget card (show loading/error/content)
                Button {
                    if hasError {
                        retryCount = 0
                        hasError = false
                        Task {
                            await loadData()
                        }
                    } else {
                        onTap?()
                    }
                } label: {
                    widgetContent
                }
                .buttonStyle(PlainButtonStyle())
            }
            .task {
                await loadData()
            }
            .task(id: isVisible) {
                // Periodic refresh when visible
                guard isVisible && isConfigured else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    guard !Task.isCancelled && isVisible else { continue }
                    await refreshData()
                }
            }
            .onAppear {
                isVisible = true
                // If we had an error, retry on appear
                if hasError {
                    Task { await loadData() }
                }
            }
            .onDisappear {
                isVisible = false
            }
        }
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header Row
            HStack {
                Image(systemName: hasError ? "exclamationmark.triangle.fill" : "server.rack")
                    .font(.system(size: 18))
                    .foregroundColor(hasError ? ColorPalette.error : ColorPalette.primary)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.textMutedDark))
                        .scaleEffect(0.7)
                } else if hasError {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Server unavailable")
                            .font(AppTypography.subheadline(.semibold))
                            .foregroundColor(ColorPalette.textPrimaryDark)

                        Text("Tap to retry")
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.error)
                    }
                } else if let systemInfo = systemInfo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(systemInfo.hostname.uppercased())
                            .font(AppTypography.subheadline(.semibold))
                            .foregroundColor(ColorPalette.textPrimaryDark)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(array?.state.isOnline == true ? ColorPalette.success : ColorPalette.warning)
                                .frame(width: 6, height: 6)
                            Text(array?.state.isOnline == true ? "Online" : "Offline")
                                .font(AppTypography.caption2())
                            .foregroundColor(array?.state.isOnline == true ? ColorPalette.success : ColorPalette.warning)
                        }
                    }
                }

                Spacer()

                Image(systemName: hasError ? "arrow.clockwise" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            if let array = array {
                // Storage Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ColorPalette.surfaceDark)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(usageColor(array.capacity.usagePercentage))
                            .frame(
                                width: geometry.size.width * min(array.capacity.usagePercentage / 100, 1.0),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                // Stats Row
                HStack {
                    Text("\(array.capacity.formattedUsed) / \(array.capacity.formattedTotal)")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textSecondaryDark)

                    Spacer()

                    Text("\(runningContainers)/\(totalContainers) containers")
                        .font(AppTypography.caption2())
                        .foregroundColor(ColorPalette.textMutedDark)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: [ColorPalette.primary.opacity(0.3), ColorPalette.secondary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func usageColor(_ percentage: Double) -> Color {
        if percentage < 70 { return ColorPalette.secondary }
        if percentage < 85 { return ColorPalette.warning }
        return ColorPalette.error
    }

    private func loadData() async {
        isLoading = true

        do {
            let data = try await UnraidService.shared.fetchAllData()
            await MainActor.run {
                self.systemInfo = data.system
                self.array = data.array
                self.runningContainers = data.containers.filter { $0.state.isRunning }.count
                self.totalContainers = data.containers.count
                self.isLoading = false
                self.hasError = false
                self.retryCount = 0  // Reset retry count on success
            }
        } catch {
            await MainActor.run {
                self.isLoading = false

                // Retry with exponential backoff
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    Task {
                        let delay = UInt64(self.retryCount) * self.retryDelaySeconds * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                        await self.loadData()
                    }
                } else {
                    self.hasError = true
                }
            }
        }
    }

    private func refreshData() async {
        // Silent refresh - don't show loading state
        do {
            let data = try await UnraidService.shared.fetchAllData()
            await MainActor.run {
                self.systemInfo = data.system
                self.array = data.array
                self.runningContainers = data.containers.filter { $0.state.isRunning }.count
                self.totalContainers = data.containers.count
                self.hasError = false
                self.retryCount = 0
            }
        } catch {
            // Silent fail for background refreshes, but reset error state if it was set
            #if DEBUG
            print("Widget refresh failed: \(error)")
            #endif
        }
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack {
            ServerHealthWidget()
        }
        .padding()
    }
}
