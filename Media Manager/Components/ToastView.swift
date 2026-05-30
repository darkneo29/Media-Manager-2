//
//  ToastView.swift
//  Media Manager
//
//  Toast notification component for displaying confirmation messages.
//

import SwiftUI

/// Toast style variants
enum ToastStyle {
    case success
    case info
    case warning
    case error

    var backgroundColor: Color {
        switch self {
        case .success: return ColorPalette.success
        case .info: return ColorPalette.info
        case .warning: return ColorPalette.warning
        case .error: return ColorPalette.error
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

/// A toast notification view that appears at the top of the screen
struct ToastView: View {
    let message: String
    let style: ToastStyle

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: style.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(AppTypography.subheadline(.medium))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(style.backgroundColor)
                .shadow(color: style.backgroundColor.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, AppSpacing.md)
    }
}

/// View modifier to show a toast notification
struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let style: ToastStyle
    let duration: TimeInterval

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                if isShowing {
                    ToastView(message: message, style: style)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isShowing = false
                                }
                            }
                        }
                }

                Spacer()
            }
            .padding(.top, AppSpacing.sm)
            .animation(.easeInOut(duration: 0.3), value: isShowing)
        }
    }
}

extension View {
    /// Shows a toast notification at the top of the view
    /// - Parameters:
    ///   - isShowing: Binding to control toast visibility
    ///   - message: The message to display
    ///   - style: The toast style (success, info, warning, error)
    ///   - duration: How long to show the toast (default 3 seconds)
    func toast(
        isShowing: Binding<Bool>,
        message: String,
        style: ToastStyle = .success,
        duration: TimeInterval = 3.0
    ) -> some View {
        self.modifier(ToastModifier(
            isShowing: isShowing,
            message: message,
            style: style,
            duration: duration
        ))
    }
}

#Preview {
    ZStack {
        ColorPalette.backgroundDark.ignoresSafeArea()

        VStack(spacing: AppSpacing.lg) {
            ToastView(message: "Search started! Radarr is looking for your movie.", style: .success)
            ToastView(message: "Something to know about.", style: .info)
            ToastView(message: "Be careful with this action.", style: .warning)
            ToastView(message: "Something went wrong.", style: .error)
        }
        .padding()
    }
}
