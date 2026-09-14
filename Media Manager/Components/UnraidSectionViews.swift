import SwiftUI

struct UnraidSectionMessage: View {
    let title: String
    let error: String?
    let updatedAt: Date?
    var body: some View {
        if let error {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title): \(error)", systemImage: "exclamationmark.triangle")
                if let updatedAt { Text("Last received \(updatedAt.formatted(date: .omitted, time: .standard))") }
            }
            .font(AppTypography.caption1())
            .foregroundColor(ColorPalette.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct UnraidParityCard: View {
    let parity: UnraidParityCheck
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("Parity check", systemImage: "checkmark.shield")
                .font(AppTypography.headline())
            Text(parity.status.replacingOccurrences(of: "_", with: " ").capitalized)
            if let progress = parity.progress, parity.running == true || parity.paused == true {
                ProgressView(value: Double(min(100, max(0, progress))), total: 100)
                Text("\(progress)% complete")
            }
            if let errors = parity.errors { Text("Errors: \(errors)").foregroundColor(errors > 0 ? ColorPalette.error : ColorPalette.textSecondaryDark) }
            if let speed = parity.speed { Text("Speed: \(speed) MB/s") }
            if let date = parity.date { Text("Last check: \(date)").font(AppTypography.caption1()) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
    }
}

struct UnraidAccessSummary: View {
    let capabilities: UnraidCapabilities
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("API \(capabilities.apiVersion ?? "version unavailable")").font(AppTypography.caption1(.semibold))
            accessRow("Docker controls", access: capabilities.dockerAction("start"))
            accessRow("VM controls", access: capabilities.vmAction("start"))
            ForEach(capabilities.issues, id: \.self) { issue in
                Text(issue).font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
            }
            Text("Refresh to recheck access after changing server permissions or updating the API.")
                .font(AppTypography.caption2()).foregroundColor(ColorPalette.textMutedDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
    }

    private func accessRow(_ name: String, access: UnraidAccess) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(name): \(label(access))").font(AppTypography.caption1())
            if let explanation = access.explanation {
                Text(explanation).font(AppTypography.caption2()).foregroundColor(ColorPalette.textSecondaryDark)
            }
        }
    }
    private func label(_ access: UnraidAccess) -> String {
        switch access {
        case .allowed: return "Allowed"
        case .denied: return "Read only / permission required"
        case .unsupported: return "Not supported"
        case .unknown: return "Not verified"
        }
    }
}

/// Metrics remain visible even when the independent hardware resolver fails.
struct UnraidMetricsCard: View {
    let metrics: MetricsData
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("System metrics", systemImage: "gauge.with.dots.needle.50percent")
                .font(AppTypography.headline())
            Text("CPU: \((metrics.cpu?.percentTotal).map { "\(Int(min(100, max(0, $0))))%" } ?? "Unavailable")")
            if let memory = metrics.memory, memory.total > 0 {
                let value = UnraidMemory(total: memory.total, used: memory.used, free: memory.free,
                                         available: memory.available, percentTotalFromAPI: memory.percentTotal)
                Text("Memory: \(Int(value.usagePercentage))%")
            } else { Text("Memory unavailable") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.lg)
    }
}
