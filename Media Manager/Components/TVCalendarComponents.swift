//
//  TVCalendarComponents.swift
//  Media Manager
//
//  tvOS-optimized calendar components with focus effects.
//

import SwiftUI

#if os(tvOS)

// MARK: - Static calendar for day component extraction

private let sharedCalendar = Calendar.current

// MARK: - TV Calendar Day Cell

/// A focusable calendar day cell for tvOS with focus effects
struct TVCalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let movieCount: Int
    let tvShowCount: Int
    let onTap: () -> Void

    @Environment(\.isFocused) private var isFocused

    private var dayNumber: String {
        "\(sharedCalendar.component(.day, from: date))"
    }

    private var hasEvents: Bool {
        movieCount > 0 || tvShowCount > 0
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xs) {
                // Day number
                Text(dayNumber)
                    .font(.system(size: 28, weight: isToday ? .bold : .medium))
                    .foregroundColor(dayTextColor)
                    .frame(width: 50, height: 50)
                    .background(dayBackground)
                    .clipShape(Circle())

                // Event indicators
                HStack(spacing: 4) {
                    if movieCount > 0 {
                        Circle()
                            .fill(ColorPalette.primary)
                            .frame(width: 10, height: 10)
                    }
                    if tvShowCount > 0 {
                        Circle()
                            .fill(ColorPalette.secondary)
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isFocused ? ColorPalette.cardBackgroundDark : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        }
        .buttonStyle(.plain)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }

    private var dayTextColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return ColorPalette.secondary
        } else if isFocused {
            return ColorPalette.textPrimaryDark
        } else {
            return ColorPalette.textPrimaryDark
        }
    }

    @ViewBuilder
    private var dayBackground: some View {
        if isSelected {
            ColorPalette.primary
        } else if isToday {
            Circle()
                .stroke(ColorPalette.secondary, lineWidth: 3)
                .background(Circle().fill(Color.clear))
        } else {
            Color.clear
        }
    }
}

// MARK: - TV Calendar Event Card

/// A focusable event card for tvOS calendar
struct TVCalendarEventCard: View {
    let event: CalendarEvent
    var isFollowed: Bool = false
    let onTap: () -> Void

    @Environment(\.isFocused) private var isFocused

    private var typeColor: Color {
        switch event.type {
        case .movieRelease:
            return ColorPalette.primary
        case .tvEpisode:
            return ColorPalette.secondary
        }
    }

    private var typeIcon: String {
        switch event.type {
        case .movieRelease:
            return "film.fill"
        case .tvEpisode:
            return "tv.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                // Poster
                CachedAsyncImage(url: event.posterURL, width: 60, height: 90)
                    .cornerRadius(AppRadius.sm)

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    // Title
                    Text(event.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Year
                    Text(String(event.year))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(typeColor)

                    // Type badge
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 14))
                        Text(event.typeLabel)
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(typeColor)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.15))
                    .cornerRadius(AppRadius.sm)

                    if isFollowed {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                            Text("Release Radar")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(ColorPalette.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : typeColor.opacity(0.3), lineWidth: isFocused ? 4 : 1)
            )
            .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        }
        .buttonStyle(.plain)
    }
}

#endif
