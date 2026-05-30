//
//  CalendarDayCell.swift
//  Media Manager
//
//  Individual day cell for the calendar grid with event indicators.
//

import SwiftUI

// MARK: - Static calendar for day component extraction

private let sharedCalendar = Calendar.current

struct CalendarDayCell: View, Equatable {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let movieCount: Int
    let tvShowCount: Int
    let onTap: () -> Void

    // Pre-compute day number once
    private var dayNumber: String {
        "\(sharedCalendar.component(.day, from: date))"
    }

    private var hasEvents: Bool {
        movieCount > 0 || tvShowCount > 0
    }

    // MARK: - Equatable (for SwiftUI diffing optimization)

    static func == (lhs: CalendarDayCell, rhs: CalendarDayCell) -> Bool {
        lhs.date == rhs.date &&
        lhs.isCurrentMonth == rhs.isCurrentMonth &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isToday == rhs.isToday &&
        lhs.movieCount == rhs.movieCount &&
        lhs.tvShowCount == rhs.tvShowCount
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xxs) {
                // Day number
                Text(dayNumber)
                    .font(AppTypography.subheadline(isToday ? .bold : .regular))
                    .foregroundColor(dayTextColor)
                    .frame(width: 32, height: 32)
                    .background(dayBackground)
                    .clipShape(Circle())

                // Event indicators
                HStack(spacing: 3) {
                    if movieCount > 0 {
                        Circle()
                            .fill(ColorPalette.primary)
                            .frame(width: 6, height: 6)
                    }
                    if tvShowCount > 0 {
                        Circle()
                            .fill(ColorPalette.secondary)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xxs)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }

    private var dayTextColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return ColorPalette.secondary
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
                .stroke(ColorPalette.secondary, lineWidth: 2)
                .background(Circle().fill(Color.clear))
        } else {
            Color.clear
        }
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        HStack(spacing: AppSpacing.xs) {
            CalendarDayCell(
                date: Date(),
                isCurrentMonth: true,
                isSelected: false,
                isToday: true,
                movieCount: 1,
                tvShowCount: 0,
                onTap: {}
            )

            CalendarDayCell(
                date: Date(),
                isCurrentMonth: true,
                isSelected: true,
                isToday: false,
                movieCount: 1,
                tvShowCount: 2,
                onTap: {}
            )

            CalendarDayCell(
                date: Date(),
                isCurrentMonth: true,
                isSelected: false,
                isToday: false,
                movieCount: 0,
                tvShowCount: 1,
                onTap: {}
            )

            CalendarDayCell(
                date: Date(),
                isCurrentMonth: false,
                isSelected: false,
                isToday: false,
                movieCount: 0,
                tvShowCount: 0,
                onTap: {}
            )
        }
        .padding()
    }
}
