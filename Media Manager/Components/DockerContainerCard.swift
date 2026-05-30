import SwiftUI

struct DockerContainerCard: View {
    let container: DockerContainer
    var isRestarting: Bool = false  // External override to show restarting state
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    @State private var isPerformingAction = false

    /// The displayed state - shows .restarting if isRestarting is true
    private var displayedState: ContainerState {
        isRestarting ? .restarting : container.state
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Container Icon
            Image(systemName: container.containerIcon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32)

            // Container Info
            VStack(alignment: .leading, spacing: 2) {
                Text(container.displayName)
                    .font(AppTypography.subheadline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    // State Badge - use displayedState to show restarting when appropriate
                    ContainerStateBadge(state: displayedState)

                    // Memory Usage (if available)
                    if let memory = container.formattedMemory {
                        Text("•")
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text(memory)
                            .font(AppTypography.caption2())
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: AppSpacing.xs) {
                if isPerformingAction {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.textSecondaryDark))
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    // Restart Button
                    ActionButton(
                        icon: "arrow.clockwise",
                        action: {
                            performAction(onRestart)
                        },
                        isEnabled: container.state.isRunning
                    )

                    // Start/Stop Button
                    if container.state.isRunning {
                        ActionButton(
                            icon: "stop.fill",
                            color: ColorPalette.warning,
                            action: {
                                performAction(onStop)
                            }
                        )
                    } else {
                        ActionButton(
                            icon: "play.fill",
                            color: ColorPalette.success,
                            action: {
                                performAction(onStart)
                            }
                        )
                    }
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(borderColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        if container.isMediaStack {
            return ColorPalette.primary
        }
        return container.state.isRunning ? ColorPalette.secondary : ColorPalette.textMutedDark
    }

    private var borderColor: Color {
        switch displayedState {
        case .running:
            return ColorPalette.success
        case .restarting:
            return ColorPalette.warning
        case .exited, .dead:
            return ColorPalette.error
        default:
            return ColorPalette.divider
        }
    }

    private func performAction(_ action: @escaping () -> Void) {
        isPerformingAction = true
        action()
        // Reset after a delay (the parent view should refresh the data)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isPerformingAction = false
        }
    }
}

// MARK: - Container State Badge

private struct ContainerStateBadge: View {
    let state: ContainerState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)

            Text(state.displayName)
                .font(AppTypography.caption2(.medium))
                .foregroundColor(stateColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(stateColor.opacity(0.15))
        .cornerRadius(AppRadius.pill)
    }

    private var stateColor: Color {
        switch state {
        case .running:
            return ColorPalette.success
        case .paused:
            return ColorPalette.warning
        case .restarting:
            return ColorPalette.info
        case .stopped, .exited, .created:
            return ColorPalette.textSecondaryDark
        case .dead, .unknown:
            return ColorPalette.error
        }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    var color: Color = ColorPalette.textSecondaryDark
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? color : ColorPalette.textDisabledDark)
                .frame(width: 32, height: 32)
                .background(ColorPalette.surfaceDark)
                .cornerRadius(8)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Compact Container Row (for grouping)

struct CompactContainerRow: View {
    let container: DockerContainer

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: container.containerIcon)
                .font(.system(size: 16))
                .foregroundColor(container.state.isRunning ? ColorPalette.success : ColorPalette.textMutedDark)
                .frame(width: 24)

            Text(container.displayName)
                .font(AppTypography.caption1())
                .foregroundColor(ColorPalette.textPrimaryDark)
                .lineLimit(1)

            Spacer()

            Circle()
                .fill(container.state.isRunning ? ColorPalette.success : ColorPalette.textMutedDark)
                .frame(width: 6, height: 6)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Container Group Card

struct ContainerGroupCard: View {
    let title: String
    let containers: [DockerContainer]
    var restartingContainerIds: Set<String> = []  // IDs of containers currently restarting
    let onStart: (DockerContainer) -> Void
    let onStop: (DockerContainer) -> Void
    let onRestart: (DockerContainer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Group Header
            HStack {
                Text(title)
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textSecondaryDark)

                Spacer()

                Text("\(runningCount)/\(containers.count) running")
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, AppSpacing.xs)

            // Container Cards
            VStack(spacing: 1) {
                ForEach(containers) { container in
                    DockerContainerCard(
                        container: container,
                        isRestarting: restartingContainerIds.contains(container.id),
                        onStart: { onStart(container) },
                        onStop: { onStop(container) },
                        onRestart: { onRestart(container) }
                    )
                }
            }
        }
    }

    private var runningCount: Int {
        containers.filter { $0.state.isRunning }.count
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // Media Stack
                ContainerGroupCard(
                    title: "MEDIA STACK",
                    containers: [
                        DockerContainer(id: "1", name: "radarr", image: "linuxserver/radarr", state: .running, status: "Up 5 days", autoStart: true, ports: ["7878:7878"], cpuUsage: 2.5, memoryUsage: 471859200),
                        DockerContainer(id: "2", name: "sonarr", image: "linuxserver/sonarr", state: .running, status: "Up 5 days", autoStart: true, ports: ["8989:8989"], cpuUsage: 1.2, memoryUsage: 398458880),
                        DockerContainer(id: "3", name: "sabnzbd", image: "linuxserver/sabnzbd", state: .running, status: "Up 5 days", autoStart: true, ports: ["8080:8080"], cpuUsage: 5.0, memoryUsage: 650117120)
                    ],
                    onStart: { _ in },
                    onStop: { _ in },
                    onRestart: { _ in }
                )

                // Other Containers
                ContainerGroupCard(
                    title: "OTHER CONTAINERS",
                    containers: [
                        DockerContainer(id: "4", name: "nginx-proxy-manager", image: "jc21/nginx-proxy-manager", state: .running, status: "Up 10 days", autoStart: true, ports: nil, cpuUsage: nil, memoryUsage: nil),
                        DockerContainer(id: "5", name: "tautulli", image: "linuxserver/tautulli", state: .stopped, status: "Exited (0) 2 hours ago", autoStart: false, ports: nil, cpuUsage: nil, memoryUsage: nil)
                    ],
                    onStart: { _ in },
                    onStop: { _ in },
                    onRestart: { _ in }
                )
            }
            .padding()
        }
    }
}
