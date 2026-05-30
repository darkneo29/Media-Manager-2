//
//  LoadingOverlay.swift
//  Media Manager
//
//  A tech-styled loading indicator overlay with gradient spinner.
//

import SwiftUI

struct LoadingOverlay: View {
    let message: String?
    @State private var isAnimating = false

    init(message: String? = nil) {
        self.message = message
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Gradient spinner
                ZStack {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.1),
                            lineWidth: 4
                        )
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "6B5CE7"),
                                    Color(hex: "00D9FF")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round
                            )
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                        .shadow(
                            color: Color(hex: "6B5CE7").opacity(0.5),
                            radius: 10,
                            x: 0,
                            y: 0
                        )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "1a1a2e"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "6B5CE7").opacity(0.3),
                                    Color(hex: "00D9FF").opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color(hex: "6B5CE7").opacity(0.3),
                    radius: 20,
                    x: 0,
                    y: 10
                )

                if let message = message {
                    Text(message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.3), value: isAnimating)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// View modifier for easy usage
extension View {
    func loadingOverlay(isShowing: Bool, message: String? = nil) -> some View {
        ZStack {
            self

            if isShowing {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            Text("Content Behind")
                .font(.title)
                .foregroundColor(.white)

            Spacer()
        }
        .padding()

        LoadingOverlay(message: "Loading movies...")
    }
}

// Preview showing the modifier usage
struct LoadingOverlayModifierPreview: View {
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Content View")
                    .font(.title)
                    .foregroundColor(.white)

                GlowingButton("Toggle Loading") {
                    isLoading.toggle()
                }
                .padding(.horizontal)
            }
        }
        .loadingOverlay(isShowing: isLoading, message: "Fetching data...")
    }
}

#Preview("With Modifier") {
    LoadingOverlayModifierPreview()
}
