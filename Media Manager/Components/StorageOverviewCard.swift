import SwiftUI

struct StorageOverviewCard: View {
    let array: UnraidArray
    var diskInventory: [UnraidDisk]? = nil
    var readingsCurrent = true

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

            UnraidCapacityView(title: "Array", capacity: array.capacity, current: readingsCurrent && array.state.isOnline)

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

            // Counts come from the independent inventory, never the compact storage query.
            if let diskInventory {
                HStack(spacing: AppSpacing.md) {
                    DiskTypeSummary(
                        icon: "shield.checkered",
                        label: "Parity",
                        count: diskInventory.filter { $0.type == .parity }.count,
                        color: ColorPalette.primary
                    )

                    DiskTypeSummary(
                        icon: "internaldrive.fill",
                        label: "Data",
                        count: diskInventory.filter { $0.type == .data }.count,
                        color: ColorPalette.secondary
                    )

                    DiskTypeSummary(
                        icon: "bolt.fill",
                        label: "Cache",
                        count: diskInventory.filter { $0.type == .cache }.count,
                        color: ColorPalette.warning
                    )
                }
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

/// Shared by array, cache, and disk displays. Only current readings generate warnings.
struct UnraidCapacityView: View {
    let title: String
    let capacity: ArrayCapacity?
    var current = true
    var compact = false
    @AppStorage("unraidStorageWarningPercent") private var warningPercent = 10

    private var level: StorageWarningLevel? {
        capacity?.warningLevel(threshold: warningPercent, current: current)
    }
    private var tint: Color {
        guard current else { return ColorPalette.textMutedDark }
        switch level {
        case .critical: return ColorPalette.error
        case .low: return ColorPalette.warning
        case nil: return ColorPalette.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if !title.isEmpty {
                Text(title).font(AppTypography.subheadline(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
            }
            if let capacity, capacity.isUsable {
                ProgressView(value: capacity.usagePercentage, total: 100).tint(tint)
                    .accessibilityLabel("\(title.isEmpty ? "Filesystem" : title) space used")
                Text("\(capacity.formattedUsed) / \(capacity.formattedTotal) used (\(Int(capacity.usagePercentage))%)")
                    .font(AppTypography.caption2()).foregroundColor(ColorPalette.textSecondaryDark)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(capacity.formattedFree) free")
                    .font(AppTypography.caption1(.medium)).foregroundColor(tint)
                if !current {
                    Text("Last known usage").font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
                } else if let level {
                    Label(level == .critical ? "Critically low space" : "Low space", systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption2(.semibold)).foregroundColor(tint)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact {
                        Text("Downloads and imports using this storage may fail. Free up space or choose another destination.")
                            .font(AppTypography.caption2()).foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
            } else {
                Text("Filesystem usage unavailable")
                    .font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct UnraidCacheStorageCard: View {
    let disks: [UnraidDisk]
    var current = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Cache storage").font(AppTypography.headline(.semibold))
                .foregroundColor(ColorPalette.textPrimaryDark)
            Text("Filesystem readings reported for each cache entry. Shared pool capacity is not added together.")
                .font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
            ForEach(disks.filter { $0.type == .cache }) { disk in
                UnraidCapacityView(title: disk.name, capacity: disk.filesystemCapacity, current: current)
            }
        }
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
    }
}
