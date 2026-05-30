import SwiftUI

struct WhatsNewView: View {
    private let releases = WhatsNewCatalog.releases

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            #if os(tvOS)
            tvOSContent
            #else
            iOSContent
            #endif
        }
        .navigationTitle("What's New")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(tvOS)
    private var tvOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVSizing.sectionSpacing) {
                heroCard

                ForEach(releases) { release in
                    TVSettingsSection(title: release.title) {
                        VStack(spacing: AppSpacing.lg) {
                            tvReleaseHeader(release)

                            ForEach(release.entries) { entry in
                                tvEntryCard(entry)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TVSizing.contentPadding)
            .padding(.vertical, TVSizing.sectionSpacing)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label {
                Text("Feature Log")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
            } icon: {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 34))
                    .foregroundColor(ColorPalette.secondary)
            }

            Text("Recent product updates live here so you can see what changed without leaving the app.")
                .font(.system(size: 24))
                .foregroundColor(ColorPalette.textSecondaryDark)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(ColorPalette.cardBackgroundDark)
        )
    }

    private func tvReleaseHeader(_ release: WhatsNewRelease) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(release.subtitle)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(ColorPalette.textPrimaryDark)

            Text("\(release.entries.count) tracked update\(release.entries.count == 1 ? "" : "s")")
                .font(.system(size: 22))
                .foregroundColor(ColorPalette.textSecondaryDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tvEntryCard(_ entry: WhatsNewEntry) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(accentColor(for: entry.kind).opacity(0.18))
                    .frame(width: 68, height: 68)

                Image(systemName: entry.kind.systemImage)
                    .font(.system(size: 30))
                    .foregroundColor(accentColor(for: entry.kind))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(entry.kind.rawValue.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accentColor(for: entry.kind))
                    .tracking(1.5)

                Text(entry.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Text(entry.description)
                    .font(.system(size: 22))
                    .foregroundColor(ColorPalette.textSecondaryDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(ColorPalette.cardBackgroundDark)
        )
    }
    #endif

    #if !os(tvOS)
    private var iOSContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                heroSection

                ForEach(releases) { release in
                    SettingsSection(title: release.title, footer: release.subtitle) {
                        ForEach(Array(release.entries.enumerated()), id: \.element.id) { index, entry in
                            whatsNewRow(entry)

                            if index < release.entries.count - 1 {
                                Divider()
                                    .background(ColorPalette.divider)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label {
                Text("Feature Log")
                    .font(AppTypography.title2())
                    .foregroundColor(ColorPalette.textPrimaryDark)
            } icon: {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
            }

            Text("This screen tracks the features and improvements added to Dragon Media Manager.")
                .font(AppTypography.body())
                .foregroundColor(ColorPalette.textSecondaryDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(ColorPalette.divider, lineWidth: 1)
        )
    }

    private func whatsNewRow(_ entry: WhatsNewEntry) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: entry.kind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accentColor(for: entry.kind))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(entry.kind.rawValue.uppercased())
                    .font(AppTypography.caption2(.semibold))
                    .foregroundColor(accentColor(for: entry.kind))

                Text(entry.title)
                    .font(AppTypography.body(.semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Text(entry.description)
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textSecondaryDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(ColorPalette.cardBackgroundDark)
    }
    #endif

    private func accentColor(for kind: WhatsNewEntryKind) -> Color {
        switch kind {
        case .newFeature:
            return ColorPalette.secondary
        case .improvement:
            return ColorPalette.info
        case .fix:
            return ColorPalette.success
        }
    }
}

#Preview {
    NavigationStack {
        WhatsNewView()
            .preferredColorScheme(.dark)
    }
}
