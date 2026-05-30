//
//  StatusBadge.swift
//  Media Manager
//
//  A pill-shaped status indicator with icon and text.
//

import SwiftUI

struct StatusBadge: View {
    let type: BadgeType

    enum BadgeType {
        case monitored
        case unmonitored
        case downloading
        case available
        case missing

        var title: String {
            switch self {
            case .monitored: return "Monitored"
            case .unmonitored: return "Unmonitored"
            case .downloading: return "Downloading"
            case .available: return "Available"
            case .missing: return "Missing"
            }
        }

        var icon: String {
            switch self {
            case .monitored: return "eye.fill"
            case .unmonitored: return "eye.slash.fill"
            case .downloading: return "arrow.down.circle.fill"
            case .available: return "checkmark.circle.fill"
            case .missing: return "exclamationmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .monitored: return Color(hex: "6B5CE7")
            case .unmonitored: return Color(hex: "6B7280")
            case .downloading: return Color(hex: "00D9FF")
            case .available: return Color(hex: "10B981")
            case .missing: return Color(hex: "F59E0B")
            }
        }

        var isActive: Bool {
            switch self {
            case .monitored, .downloading, .available:
                return true
            case .unmonitored, .missing:
                return false
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))

            Text(type.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(type.color.opacity(0.9))
        )
        .overlay(
            Capsule()
                .stroke(type.color.opacity(0.5), lineWidth: 1)
        )
        .shadow(
            color: type.isActive ? type.color.opacity(0.4) : .clear,
            radius: type.isActive ? 6 : 0,
            x: 0,
            y: 2
        )
    }
}


#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            StatusBadge(type: .monitored)
            StatusBadge(type: .unmonitored)
            StatusBadge(type: .downloading)
            StatusBadge(type: .available)
            StatusBadge(type: .missing)
        }
        .padding()
    }
}
