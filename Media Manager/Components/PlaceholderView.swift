//
//  PlaceholderView.swift
//  Media Manager
//
//  Reusable empty state and placeholder view with icon, text, and optional action.
//

import SwiftUI

struct PlaceholderView: View {
    let icon: String
    let title: String
    let description: String
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
        icon: String,
        title: String,
        description: String,
        action: ActionConfig? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.action = action
    }

    var body: some View {
        VStack(spacing: 24) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "6B5CE7").opacity(0.2),
                                Color(hex: "00D9FF").opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(
                        color: Color(hex: "6B5CE7").opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )

                Image(systemName: icon)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: "6B5CE7"),
                                Color(hex: "00D9FF")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }

            if let action = action {
                GlowingButton(
                    action.title,
                    icon: action.icon,
                    variant: .primary,
                    action: action.handler
                )
                .padding(.horizontal, 48)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        TabView {
            PlaceholderView(
                icon: "film.stack",
                title: "No Movies Yet",
                description: "Start building your collection by adding your first movie",
                action: PlaceholderView.ActionConfig(
                    title: "Add Movie",
                    icon: "plus.circle.fill",
                    handler: { print("Add movie tapped") }
                )
            )
            .tag(0)

            PlaceholderView(
                icon: "sparkles",
                title: "Coming Soon",
                description: "This feature is currently under development and will be available in a future update"
            )
            .tag(1)

            PlaceholderView(
                icon: "magnifyingglass",
                title: "No Results Found",
                description: "Try adjusting your search or filter to find what you're looking for",
                action: PlaceholderView.ActionConfig(
                    title: "Clear Filters",
                    icon: "xmark.circle.fill",
                    handler: { print("Clear filters tapped") }
                )
            )
            .tag(2)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
