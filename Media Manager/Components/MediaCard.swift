//
//  MediaCard.swift
//  Media Manager
//
//  A reusable card component for displaying media items with poster,
//  title, subtitle, and optional status badge.
//

import SwiftUI

struct MediaCard: View {
    let imageURL: String?
    let title: String
    let subtitle: String?
    let badge: StatusBadge.BadgeType?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // Poster image
                    ZStack(alignment: .bottom) {
                        if let imageURL = imageURL, let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url, width: 160, height: 240)
                        } else {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "1a1a2e"),
                                            Color(hex: "16213e")
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 240)
                                .overlay {
                                    Image(systemName: "film")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.2))
                                }
                        }

                        // Title overlay with gradient
                        VStack(spacing: 4) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            if let subtitle = subtitle {
                                Text(subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0),
                                    Color.black.opacity(0.7),
                                    Color.black.opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .background(Color(hex: "0f0f1e"))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "6B5CE7").opacity(0.3),
                                    Color(hex: "00D9FF").opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color(hex: "6B5CE7").opacity(0.2),
                    radius: 8,
                    x: 0,
                    y: 4
                )

                // Badge overlay
                if let badgeType = badge {
                    StatusBadge(type: badgeType)
                        .padding(8)
                }
            }
        }
        .buttonStyle(CardButtonStyle())
    }
}

// Custom button style for card interaction
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Note: Color(hex:) extension is defined in Theme/AppTheme.swift

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            HStack(spacing: 16) {
                MediaCard(
                    imageURL: nil,
                    title: "The Matrix",
                    subtitle: "1999",
                    badge: .monitored,
                    onTap: {}
                )

                MediaCard(
                    imageURL: nil,
                    title: "Inception",
                    subtitle: "2010",
                    badge: .downloading,
                    onTap: {}
                )
            }
            .padding(.horizontal)
        }
    }
}
