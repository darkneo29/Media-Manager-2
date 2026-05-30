import SwiftUI

struct DiskCard: View {
    let disk: UnraidDisk
    @AppStorage("unraidTemperatureUnit") private var temperatureUnit: String = "celsius"

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Disk Icon
            Image(systemName: diskIcon)
                .font(.system(size: 20))
                .foregroundColor(diskTypeColor)
                .frame(width: 32)

            // Disk Info
            VStack(alignment: .leading, spacing: 2) {
                Text(disk.name)
                    .font(AppTypography.subheadline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Text(disk.formattedSize)
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }

            Spacer()

            // Temperature
            if let temp = disk.temperature {
                TemperatureBadge(
                    temperature: temp,
                    unit: temperatureUnit,
                    level: disk.temperatureColor
                )
            }

            // Status Indicator
            StatusIndicator(status: disk.status)
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(statusBorderColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var diskIcon: String {
        switch disk.type {
        case .parity:
            return "shield.checkered"
        case .cache:
            return "bolt.fill"
        case .flash:
            return "memorychip.fill"
        case .data, .unknown:
            return "internaldrive.fill"
        }
    }

    private var diskTypeColor: Color {
        switch disk.type {
        case .parity:
            return ColorPalette.primary
        case .cache:
            return ColorPalette.warning
        case .flash:
            return ColorPalette.info
        case .data, .unknown:
            return ColorPalette.secondary
        }
    }

    private var statusBorderColor: Color {
        switch disk.status {
        case .healthy:
            return ColorPalette.success
        case .warning:
            return ColorPalette.warning
        case .error:
            return ColorPalette.error
        case .spunDown:
            return ColorPalette.textMutedDark
        default:
            return ColorPalette.divider
        }
    }
}

// MARK: - Temperature Badge

private struct TemperatureBadge: View {
    let temperature: Int
    let unit: String
    let level: UnraidDisk.TemperatureLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: temperatureIcon)
                .font(.system(size: 10))
                .foregroundColor(temperatureColor)

            Text(formattedTemperature)
                .font(AppTypography.caption2(.medium))
                .foregroundColor(temperatureColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(temperatureColor.opacity(0.15))
        .cornerRadius(AppRadius.sm)
    }

    private var formattedTemperature: String {
        if unit == "fahrenheit" {
            let fahrenheit = Int(Double(temperature) * 9.0 / 5.0 + 32)
            return "\(fahrenheit)°F"
        }
        return "\(temperature)°C"
    }

    private var temperatureIcon: String {
        switch level {
        case .cool:
            return "thermometer.snowflake"
        case .normal:
            return "thermometer.low"
        case .warm:
            return "thermometer.medium"
        case .hot:
            return "thermometer.high"
        case .unknown:
            return "thermometer"
        }
    }

    private var temperatureColor: Color {
        switch level {
        case .cool:
            return ColorPalette.info
        case .normal:
            return ColorPalette.success
        case .warm:
            return ColorPalette.warning
        case .hot:
            return ColorPalette.error
        case .unknown:
            return ColorPalette.textMutedDark
        }
    }
}

// MARK: - Status Indicator

private struct StatusIndicator: View {
    let status: DiskStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if status != .healthy {
                Text(status.displayName)
                    .font(AppTypography.caption2())
                    .foregroundColor(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .healthy:
            return ColorPalette.success
        case .warning:
            return ColorPalette.warning
        case .error:
            return ColorPalette.error
        case .spunDown:
            return ColorPalette.textMutedDark
        case .disabled:
            return ColorPalette.textDisabledDark
        case .missing, .unknown:
            return ColorPalette.error
        }
    }
}

// MARK: - Compact Disk Grid Card

struct CompactDiskCard: View {
    let disk: UnraidDisk
    @AppStorage("unraidTemperatureUnit") private var temperatureUnit: String = "celsius"

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Header
            HStack {
                Image(systemName: diskIcon)
                    .font(.system(size: 14))
                    .foregroundColor(diskTypeColor)

                Text(disk.name)
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            // Size and Temp
            HStack {
                Text(disk.formattedSize)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textSecondaryDark)

                Spacer()

                if let temp = disk.temperature {
                    Text(formatTemperature(temp))
                        .font(AppTypography.caption2(.medium))
                        .foregroundColor(tempColor)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(ColorPalette.surfaceDark)
        .cornerRadius(AppRadius.sm)
    }

    private var diskIcon: String {
        switch disk.type {
        case .parity: return "shield.checkered"
        case .cache: return "bolt.fill"
        case .flash: return "memorychip.fill"
        case .data, .unknown: return "internaldrive.fill"
        }
    }

    private var diskTypeColor: Color {
        switch disk.type {
        case .parity: return ColorPalette.primary
        case .cache: return ColorPalette.warning
        case .flash: return ColorPalette.info
        case .data, .unknown: return ColorPalette.secondary
        }
    }

    private var statusColor: Color {
        switch disk.status {
        case .healthy: return ColorPalette.success
        case .warning: return ColorPalette.warning
        case .error: return ColorPalette.error
        case .spunDown: return ColorPalette.textMutedDark
        default: return ColorPalette.textDisabledDark
        }
    }

    private var tempColor: Color {
        switch disk.temperatureColor {
        case .cool: return ColorPalette.info
        case .normal: return ColorPalette.success
        case .warm: return ColorPalette.warning
        case .hot: return ColorPalette.error
        case .unknown: return ColorPalette.textMutedDark
        }
    }

    private func formatTemperature(_ temp: Int) -> String {
        if temperatureUnit == "fahrenheit" {
            let fahrenheit = Int(Double(temp) * 9.0 / 5.0 + 32)
            return "\(fahrenheit)°F"
        }
        return "\(temp)°C"
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.sm) {
            DiskCard(
                disk: UnraidDisk(
                    id: "1",
                    name: "Parity",
                    size: 17592186044416, // 16 TB
                    used: 0,
                    status: .healthy,
                    temperature: 34,
                    type: .parity,
                    device: "sda",
                    serial: nil
                )
            )

            DiskCard(
                disk: UnraidDisk(
                    id: "2",
                    name: "Disk 1",
                    size: 15032385536000, // 14 TB
                    used: 12000000000000,
                    status: .healthy,
                    temperature: 31,
                    type: .data,
                    device: "sdb",
                    serial: nil
                )
            )

            DiskCard(
                disk: UnraidDisk(
                    id: "3",
                    name: "Disk 2",
                    size: 15032385536000,
                    used: 14000000000000,
                    status: .spunDown,
                    temperature: nil,
                    type: .data,
                    device: "sdc",
                    serial: nil
                )
            )

            DiskCard(
                disk: UnraidDisk(
                    id: "4",
                    name: "Cache",
                    size: 1099511627776, // 1 TB
                    used: 500000000000,
                    status: .healthy,
                    temperature: 52,
                    type: .cache,
                    device: "nvme0n1",
                    serial: nil
                )
            )
        }
        .padding()
    }
}
