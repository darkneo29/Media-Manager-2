import SwiftUI

struct SystemStatusCard: View {
    let systemInfo: UnraidSystemInfo
    let arrayState: ArrayState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header Row
            HStack(alignment: .top) {
                // Server Icon and Name
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(systemInfo.hostname.uppercased())
                            .font(AppTypography.headline(.bold))
                            .foregroundColor(ColorPalette.textPrimaryDark)

                        HStack(spacing: AppSpacing.xs) {
                            StatusDot(isOnline: arrayState.isOnline)
                            Text(arrayState.isOnline ? "Online" : arrayState.displayName)
                                .font(AppTypography.caption1())
                                .foregroundColor(arrayState.isOnline ? ColorPalette.success : ColorPalette.warning)
                        }
                    }
                }

                Spacer()

                // Uptime Badge
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.textMutedDark)
                    Text(systemInfo.formattedUptime)
                        .font(AppTypography.caption2(.medium))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 4)
                .background(ColorPalette.surfaceDark)
                .cornerRadius(AppRadius.sm)
            }

            // Version Info
            Text("Unraid \(systemInfo.version) • \(systemInfo.cpu.model)")
                .font(AppTypography.caption1())
                .foregroundColor(ColorPalette.textMutedDark)
                .lineLimit(1)

            // Stats Row
            HStack(spacing: AppSpacing.sm) {
                // CPU Usage
                StatMiniCard(
                    icon: "cpu",
                    label: "CPU",
                    value: "\(systemInfo.cpu.cores) cores",
                    color: ColorPalette.primary
                )

                // RAM Usage
                StatMiniCard(
                    icon: "memorychip",
                    label: "RAM",
                    value: formatMemoryUsage(),
                    progress: systemInfo.memory.usagePercentage / 100,
                    color: ColorPalette.secondary
                )

                // Temperature (if available)
                if let temp = systemInfo.cpu.temperature {
                    StatMiniCard(
                        icon: "thermometer.medium",
                        label: "Temp",
                        value: formatTemperature(temp),
                        color: temperatureColor(temp)
                    )
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
                        colors: [ColorPalette.primary.opacity(0.3), ColorPalette.secondary.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func formatMemoryUsage() -> String {
        let percentage = Int(systemInfo.memory.usagePercentage)
        return "\(percentage)%"
    }

    private func formatTemperature(_ temp: Double) -> String {
        return "\(Int(temp))°C"
    }

    private func temperatureColor(_ temp: Double) -> Color {
        if temp < 50 { return ColorPalette.success }
        if temp < 70 { return ColorPalette.warning }
        return ColorPalette.error
    }
}

// MARK: - Status Dot

private struct StatusDot: View {
    let isOnline: Bool

    var body: some View {
        Circle()
            .fill(isOnline ? ColorPalette.success : ColorPalette.warning)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(isOnline ? ColorPalette.success.opacity(0.3) : ColorPalette.warning.opacity(0.3), lineWidth: 2)
            )
    }
}

// MARK: - Stat Mini Card

private struct StatMiniCard: View {
    let icon: String
    let label: String
    let value: String
    var progress: Double? = nil
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            // Value
            Text(value)
                .font(AppTypography.caption1(.semibold))
                .foregroundColor(ColorPalette.textPrimaryDark)

            // Optional Progress Bar
            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorPalette.surfaceDark)
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geometry.size.width * min(progress, 1.0), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.xs)
        .background(ColorPalette.surfaceDark)
        .cornerRadius(AppRadius.sm)
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        SystemStatusCard(
            systemInfo: UnraidSystemInfo(
                hostname: "TOWER",
                version: "7.2.0",
                uptime: 3672000, // ~42 days
                cpu: UnraidCPU(
                    model: "Intel Core i7-10700",
                    cores: 8,
                    usage: 23,
                    temperature: 45
                ),
                memory: UnraidMemory(
                    total: 68719476736, // 64 GB
                    used: 30923764531, // ~29 GB
                    free: 37795712205,
                    available: 45000000000, // ~42 GB available
                    percentTotalFromAPI: 45.0 // 45% usage
                )
            ),
            arrayState: .started
        )
        .padding()
    }
}
