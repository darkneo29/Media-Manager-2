import SwiftUI

struct ReleaseRadarFilterBar: View {
    let enabledFilters: Set<ReleaseRadarEventFilter>
    let onToggle: (ReleaseRadarEventFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(ReleaseRadarEventFilter.allCases) { filter in
                    let isEnabled = enabledFilters.contains(filter)

                    Button {
                        onToggle(filter)
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(filter.shortTitle)
                                .font(AppTypography.caption1(.semibold))
                        }
                        .foregroundColor(isEnabled ? .white : ColorPalette.textSecondaryDark)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(
                            Capsule()
                                .fill(isEnabled ? filterColor(for: filter) : ColorPalette.cardBackgroundDark)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isEnabled ? filterColor(for: filter).opacity(0.35) : ColorPalette.divider,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
        }
    }

    private func filterColor(for filter: ReleaseRadarEventFilter) -> Color {
        switch filter {
        case .theatrical:
            return ColorPalette.primary
        case .digital:
            return ColorPalette.secondary
        case .physical:
            return ColorPalette.warning
        case .tvEpisodes:
            return ColorPalette.success
        }
    }
}
