//
//  SectionHeader.swift
//  Media Manager
//
//  Styled section headers with optional subtitle and trailing action.
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let action: ActionConfig?

    struct ActionConfig {
        let title: String
        let icon: String?
        let handler: () -> Void

        init(title: String, icon: String? = nil, handler: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.handler = handler
        }
    }

    init(
        _ title: String,
        subtitle: String? = nil,
        action: ActionConfig? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                if let action = action {
                    Button(action: action.handler) {
                        HStack(spacing: 6) {
                            if let icon = action.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 14, weight: .semibold))
                            }

                            Text(action.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "6B5CE7"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(hex: "6B5CE7").opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "6B5CE7").opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.bottom, 12)

            // Gradient underline
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "6B5CE7"),
                            Color(hex: "00D9FF")
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .shadow(
                    color: Color(hex: "6B5CE7").opacity(0.5),
                    radius: 4,
                    x: 0,
                    y: 2
                )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            SectionHeader(
                "Movies",
                subtitle: "124 items"
            )

            SectionHeader(
                "Recently Added",
                subtitle: "Last 7 days",
                action: SectionHeader.ActionConfig(
                    title: "View All",
                    icon: "arrow.right",
                    handler: { print("View all tapped") }
                )
            )

            SectionHeader(
                "Settings",
                action: SectionHeader.ActionConfig(
                    title: "Edit",
                    icon: "pencil",
                    handler: { print("Edit tapped") }
                )
            )

            Spacer()
        }
        .padding(.top, 40)
    }
}
