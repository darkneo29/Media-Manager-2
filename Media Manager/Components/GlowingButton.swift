//
//  GlowingButton.swift
//  Media Manager
//
//  A stylized button component with glow effects and multiple variants.
//

import SwiftUI

struct GlowingButton: View {
    let title: String
    let icon: String?
    let variant: ButtonVariant
    let action: () -> Void

    @State private var isPressed = false

    enum ButtonVariant {
        case primary
        case secondary
        case destructive

        var backgroundColor: Color {
            switch self {
            case .primary: return Color(hex: "6B5CE7")
            case .secondary: return Color.clear
            case .destructive: return Color(hex: "EF4444")
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary, .destructive: return .white
            case .secondary: return Color(hex: "6B5CE7")
            }
        }

        var borderColor: Color {
            switch self {
            case .primary, .destructive: return .clear
            case .secondary: return Color(hex: "6B5CE7")
            }
        }

        var glowColor: Color {
            switch self {
            case .primary: return Color(hex: "6B5CE7")
            case .secondary: return Color(hex: "6B5CE7")
            case .destructive: return Color(hex: "EF4444")
            }
        }
    }

    init(
        _ title: String,
        icon: String? = nil,
        variant: ButtonVariant = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(variant.foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(variant.backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(variant.borderColor, lineWidth: variant == .secondary ? 2 : 0)
            )
            .shadow(
                color: variant.glowColor.opacity(isPressed ? 0.5 : 0.3),
                radius: isPressed ? 12 : 8,
                x: 0,
                y: isPressed ? 6 : 4
            )
        }
        .buttonStyle(PressEffectButtonStyle(isPressed: $isPressed))
    }
}

struct PressEffectButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            GlowingButton("Add Movie", icon: "plus.circle.fill", variant: .primary) {
                print("Primary tapped")
            }

            GlowingButton("Cancel", icon: "xmark", variant: .secondary) {
                print("Secondary tapped")
            }

            GlowingButton("Delete", icon: "trash.fill", variant: .destructive) {
                print("Destructive tapped")
            }

            GlowingButton("Search", icon: "magnifyingglass") {
                print("Search tapped")
            }
        }
        .padding()
    }
}
