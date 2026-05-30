import SwiftUI

struct StorageOverviewCard: View {
    let array: UnraidArray

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack {
                Text("Storage")
                    .font(AppTypography.headline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                // Array State Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(array.state.isOnline ? ColorPalette.success : ColorPalette.warning)
                        .frame(width: 6, height: 6)
                    Text(array.state.displayName)
                        .font(AppTypography.caption2(.medium))
                        .foregroundColor(array.state.isOnline ? ColorPalette.success : ColorPalette.warning)
                }
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 4)
                .background(
                    (array.state.isOnline ? ColorPalette.success : ColorPalette.warning).opacity(0.15)
                )
                .cornerRadius(AppRadius.pill)
            }

            // Capacity Section
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ColorPalette.surfaceDark)
                            .frame(height: 12)

                        // Used Space
                        RoundedRectangle(cornerRadius: 6)
                            .fill(usageGradient)
                            .frame(
                                width: geometry.size.width * min(array.capacity.usagePercentage / 100, 1.0),
                                height: 12
                            )
                    }
                }
                .frame(height: 12)

                // Capacity Text
                HStack {
                    Text("\(array.capacity.formattedUsed) / \(array.capacity.formattedTotal)")
                        .font(AppTypography.subheadline(.medium))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    Text("\(Int(array.capacity.usagePercentage))% used")
                        .font(AppTypography.caption1())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                // Free Space
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundColor(ColorPalette.success)
                    Text("\(array.capacity.formattedFree) free")
                        .font(AppTypography.caption1())
                        .foregroundColor(ColorPalette.success)
                }
            }

            // Parity Status (if available)
            if let parity = array.parity {
                Divider()
                    .background(ColorPalette.divider)

                HStack {
                    Image(systemName: parity.valid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(parity.valid ? ColorPalette.success : ColorPalette.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(parity.valid ? "Parity Valid" : "Parity Invalid")
                            .font(AppTypography.caption1(.medium))
                            .foregroundColor(ColorPalette.textPrimaryDark)

                        if parity.inProgress, let progress = parity.progress {
                            Text("Check in progress: \(Int(progress))%")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.info)
                        } else if let lastCheck = parity.lastCheckFormatted {
                            Text("Last check: \(lastCheck)")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                        }
                    }

                    Spacer()

                    if let errors = parity.errors, errors > 0 {
                        Text("\(errors) errors")
                            .font(AppTypography.caption2(.medium))
                            .foregroundColor(ColorPalette.error)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ColorPalette.error.opacity(0.15))
                            .cornerRadius(AppRadius.sm)
                    }
                }
            }

            // Disk Summary
            HStack(spacing: AppSpacing.md) {
                DiskTypeSummary(
                    icon: "shield.checkered",
                    label: "Parity",
                    count: array.disks.filter { $0.type == .parity }.count,
                    color: ColorPalette.primary
                )

                DiskTypeSummary(
                    icon: "internaldrive.fill",
                    label: "Data",
                    count: array.disks.filter { $0.type == .data }.count,
                    color: ColorPalette.secondary
                )

                DiskTypeSummary(
                    icon: "bolt.fill",
                    label: "Cache",
                    count: array.disks.filter { $0.type == .cache }.count,
                    color: ColorPalette.warning
                )
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }

    private var usageGradient: LinearGradient {
        let percentage = array.capacity.usagePercentage
        let colors: [Color]

        if percentage < 70 {
            colors = [ColorPalette.secondary, ColorPalette.secondaryDark]
        } else if percentage < 85 {
            colors = [ColorPalette.warning, ColorPalette.warningDark]
        } else {
            colors = [ColorPalette.error, ColorPalette.errorDark]
        }

        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Disk Type Summary

private struct DiskTypeSummary: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
                Text(label)
                    .font(AppTypography.caption2())
                    .foregroundColor(ColorPalette.textMutedDark)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        StorageOverviewCard(
            array: UnraidArray(
                state: .started,
                capacity: ArrayCapacity(
                    total: 107374182400000, // 100 TB
                    used: 72103024640000,   // 67.2 TB
                    free: 35271157760000    // 32.8 TB
                ),
                disks: [
                    UnraidDisk(id: "1", name: "Parity", size: 17592186044416, used: 0, status: .healthy, temperature: 34, type: .parity, device: "sda", serial: nil),
                    UnraidDisk(id: "2", name: "Disk 1", size: 15032385536000, used: 12000000000000, status: .healthy, temperature: 31, type: .data, device: "sdb", serial: nil),
                    UnraidDisk(id: "3", name: "Disk 2", size: 15032385536000, used: 14000000000000, status: .healthy, temperature: 32, type: .data, device: "sdc", serial: nil),
                    UnraidDisk(id: "4", name: "Disk 3", size: 13194139533312, used: 10000000000000, status: .spunDown, temperature: 29, type: .data, device: "sdd", serial: nil),
                    UnraidDisk(id: "5", name: "Cache", size: 1099511627776, used: 500000000000, status: .healthy, temperature: 38, type: .cache, device: "nvme0n1", serial: nil)
                ],
                parity: ParityStatus(valid: true, lastCheck: Date().addingTimeInterval(-86400 * 14), inProgress: false, progress: nil, speed: nil, errors: 0)
            )
        )
        .padding()
    }
}
