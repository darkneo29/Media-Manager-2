import SwiftUI

struct VMCard: View {
    let vm: VmDomain
    var isRestarting: Bool = false
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onForceStop: () -> Void

    @State private var isPerformingAction = false
    @State private var showForceStopConfirmation = false

    /// The displayed state - shows restarting if isRestarting is true
    private var displayedState: VmState {
        isRestarting ? .unknown : vm.state
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // VM Icon
            Image(systemName: vm.vmIcon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32)

            // VM Info
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.displayName)
                    .font(AppTypography.subheadline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)

                VmStateBadge(state: displayedState, isRestarting: isRestarting)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: AppSpacing.xs) {
                if isPerformingAction || isRestarting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.textSecondaryDark))
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    // Restart Button (only when running)
                    VmActionButton(
                        icon: "arrow.clockwise",
                        action: {
                            performAction(onRestart)
                        },
                        isEnabled: vm.state.isRunning
                    )

                    // Start/Stop Button
                    if vm.state.isRunning {
                        VmActionButton(
                            icon: "stop.fill",
                            color: ColorPalette.warning,
                            action: {
                                performAction(onStop)
                            }
                        )
                        .onLongPressGesture(minimumDuration: 1.0) {
                            showForceStopConfirmation = true
                        }
                    } else {
                        VmActionButton(
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
        .confirmationDialog("Force Stop VM", isPresented: $showForceStopConfirmation, titleVisibility: .visible) {
            Button("Force Stop", role: .destructive) {
                performAction(onForceStop)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is like pulling the power plug. The VM will be immediately terminated without graceful shutdown. This may cause data loss.")
        }
    }

    private var iconColor: Color {
        vm.state.isRunning ? ColorPalette.secondary : ColorPalette.textMutedDark
    }

    private var borderColor: Color {
        if isRestarting {
            return ColorPalette.warning
        }
        switch vm.state {
        case .running:
            return ColorPalette.success
        case .paused:
            return ColorPalette.warning
        case .crashed:
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

// MARK: - VM State Badge

private struct VmStateBadge: View {
    let state: VmState
    var isRestarting: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if isRestarting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: ColorPalette.warning))
                    .scaleEffect(0.5)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
            }

            Text(isRestarting ? "Restarting" : state.displayName)
                .font(AppTypography.caption2(.medium))
                .foregroundColor(isRestarting ? ColorPalette.warning : stateColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isRestarting ? ColorPalette.warning : stateColor).opacity(0.15))
        .cornerRadius(AppRadius.pill)
    }

    private var stateColor: Color {
        switch state {
        case .running:
            return ColorPalette.success
        case .paused, .suspended:
            return ColorPalette.warning
        case .stopped, .idle:
            return ColorPalette.textSecondaryDark
        case .crashed, .unknown:
            return ColorPalette.error
        }
    }
}

// MARK: - VM Action Button

private struct VmActionButton: View {
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

// MARK: - VM Group Card

struct VMGroupCard: View {
    let vms: [VmDomain]
    var restartingVmIds: Set<String> = []
    let onStart: (VmDomain) -> Void
    let onStop: (VmDomain) -> Void
    let onRestart: (VmDomain) -> Void
    let onForceStop: (VmDomain) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Group Header
            HStack {
                Image(systemName: "cube.fill")
                    .foregroundColor(ColorPalette.primary)
                Text("Virtual Machines")
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textSecondaryDark)

                Spacer()

                Text("\(runningCount)/\(vms.count) running")
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, AppSpacing.xs)

            // VM Cards
            VStack(spacing: AppSpacing.xs) {
                ForEach(vms) { vm in
                    VMCard(
                        vm: vm,
                        isRestarting: restartingVmIds.contains(vm.id),
                        onStart: { onStart(vm) },
                        onStop: { onStop(vm) },
                        onRestart: { onRestart(vm) },
                        onForceStop: { onForceStop(vm) }
                    )
                }
            }
        }
    }

    private var runningCount: Int {
        vms.filter { $0.state.isRunning }.count
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        ScrollView {
            VStack(spacing: AppSpacing.md) {
                VMGroupCard(
                    vms: [
                        VmDomain(id: "1", name: "hassio", uuid: "abc-123", state: .running),
                        VmDomain(id: "2", name: "Windows 11", uuid: "def-456", state: .stopped),
                        VmDomain(id: "3", name: "Ubuntu Server", uuid: "ghi-789", state: .paused)
                    ],
                    onStart: { _ in },
                    onStop: { _ in },
                    onRestart: { _ in },
                    onForceStop: { _ in }
                )
            }
            .padding()
        }
    }
}
