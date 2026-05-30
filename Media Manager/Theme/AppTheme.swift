//
//  AppTheme.swift
//  Media Manager
//
//  Created on 2025-12-24.
//

import SwiftUI

// MARK: - Color Palette

struct ColorPalette {
    // MARK: - Primary Colors
    static let primary = Color(hex: "6B5CE7")
    static let primaryDark = Color(hex: "5847C7")
    static let primaryLight = Color(hex: "8B7FF5")

    static let secondary = Color(hex: "00D9FF")
    static let secondaryDark = Color(hex: "00B8D9")
    static let secondaryLight = Color(hex: "33E3FF")

    // MARK: - Background Colors (Dark Mode)
    static let backgroundDark = Color(hex: "0D0D0F")
    static let surfaceDark = Color(hex: "1A1A1E")
    static let cardBackgroundDark = Color(hex: "242428")
    static let cardBackgroundElevatedDark = Color(hex: "2C2C32")

    // MARK: - Background Colors (Light Mode)
    static let backgroundLight = Color(hex: "F8F9FA")
    static let surfaceLight = Color(hex: "FFFFFF")
    static let cardBackgroundLight = Color(hex: "FFFFFF")
    static let cardBackgroundElevatedLight = Color(hex: "F1F3F5")

    // MARK: - Text Colors (Dark Mode)
    static let textPrimaryDark = Color(hex: "FFFFFF")
    static let textSecondaryDark = Color(hex: "B4B4B8")
    static let textMutedDark = Color(hex: "707078")
    static let textDisabledDark = Color(hex: "4A4A52")

    // MARK: - Text Colors (Light Mode)
    static let textPrimaryLight = Color(hex: "1A1A1E")
    static let textSecondaryLight = Color(hex: "6C6C72")
    static let textMutedLight = Color(hex: "9C9CA4")
    static let textDisabledLight = Color(hex: "C8C8CE")

    // MARK: - Status Colors
    static let success = Color(hex: "10B981")
    static let successDark = Color(hex: "059669")
    static let successLight = Color(hex: "34D399")

    static let warning = Color(hex: "F59E0B")
    static let warningDark = Color(hex: "D97706")
    static let warningLight = Color(hex: "FBBF24")

    static let error = Color(hex: "EF4444")
    static let errorDark = Color(hex: "DC2626")
    static let errorLight = Color(hex: "F87171")

    static let info = Color(hex: "3B82F6")
    static let infoDark = Color(hex: "2563EB")
    static let infoLight = Color(hex: "60A5FA")

    // MARK: - Semantic Colors
    static let overlay = Color.black.opacity(0.6)
    static let overlayLight = Color.black.opacity(0.3)
    static let divider = Color.white.opacity(0.1)
    static let dividerLight = Color.black.opacity(0.1)

    // MARK: - Gradient Colors
    static let primaryGradient = LinearGradient(
        colors: [primary, primaryDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let secondaryGradient = LinearGradient(
        colors: [secondary, secondaryDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [primary, secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [backgroundDark, surfaceDark],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography System

struct AppTypography {
    // MARK: - Font Weights
    enum FontWeight {
        case light, regular, medium, semibold, bold, heavy

        var weight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }

    // MARK: - Title Styles
    static func largeTitle(_ weight: FontWeight = .bold) -> Font {
        .system(size: 34, weight: weight.weight, design: .default)
    }

    static func title1(_ weight: FontWeight = .bold) -> Font {
        .system(size: 28, weight: weight.weight, design: .default)
    }

    static func title2(_ weight: FontWeight = .bold) -> Font {
        .system(size: 22, weight: weight.weight, design: .default)
    }

    static func title3(_ weight: FontWeight = .semibold) -> Font {
        .system(size: 20, weight: weight.weight, design: .default)
    }

    // MARK: - Headline & Body Styles
    static func headline(_ weight: FontWeight = .semibold) -> Font {
        .system(size: 17, weight: weight.weight, design: .default)
    }

    static func body(_ weight: FontWeight = .regular) -> Font {
        .system(size: 17, weight: weight.weight, design: .default)
    }

    static func callout(_ weight: FontWeight = .regular) -> Font {
        .system(size: 16, weight: weight.weight, design: .default)
    }

    static func subheadline(_ weight: FontWeight = .regular) -> Font {
        .system(size: 15, weight: weight.weight, design: .default)
    }

    static func footnote(_ weight: FontWeight = .regular) -> Font {
        .system(size: 13, weight: weight.weight, design: .default)
    }

    static func caption1(_ weight: FontWeight = .regular) -> Font {
        .system(size: 12, weight: weight.weight, design: .default)
    }

    static func caption2(_ weight: FontWeight = .regular) -> Font {
        .system(size: 11, weight: weight.weight, design: .default)
    }

    // MARK: - Custom Styles
    static func overline(_ weight: FontWeight = .semibold) -> Font {
        .system(size: 11, weight: weight.weight, design: .default)
    }

    static func button(_ weight: FontWeight = .semibold) -> Font {
        .system(size: 17, weight: weight.weight, design: .default)
    }

    static func monospacedDigit(_ size: CGFloat = 17) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - Spacing System

struct AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64

    // MARK: - Semantic Spacing
    static let cardPadding: CGFloat = md
    static let sectionSpacing: CGFloat = lg
    static let listItemSpacing: CGFloat = xs
    static let horizontalMargin: CGFloat = md
}

// MARK: - tvOS Sizing System

/// Platform-adaptive sizing for TV vs mobile experiences
struct TVSizing {
    // MARK: - Check Platform
    static var isTV: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Poster Sizes
    /// Poster width for grid layouts
    static var posterWidth: CGFloat {
        #if os(tvOS)
        return 220
        #else
        return 130
        #endif
    }

    /// Poster height for grid layouts (1.5:1 aspect ratio)
    static var posterHeight: CGFloat {
        #if os(tvOS)
        return 330
        #else
        return 195
        #endif
    }

    /// Large poster for detail views
    static var largePosterWidth: CGFloat {
        #if os(tvOS)
        return 300
        #else
        return 160
        #endif
    }

    static var largePosterHeight: CGFloat {
        #if os(tvOS)
        return 450
        #else
        return 240
        #endif
    }

    /// Bookshelf card poster size
    static var bookshelfPosterWidth: CGFloat {
        #if os(tvOS)
        return 140
        #else
        return 70
        #endif
    }

    static var bookshelfPosterHeight: CGFloat {
        #if os(tvOS)
        return 210
        #else
        return 105
        #endif
    }

    // MARK: - Grid Columns
    /// Number of columns for poster grids (reduced on tvOS for better performance)
    static var gridColumns: Int {
        #if os(tvOS)
        return 4  // Reduced from 6 to minimize simultaneous renders
        #else
        return 4
        #endif
    }

    /// Number of columns for list/card grids
    static var listGridColumns: Int {
        #if os(tvOS)
        return 2
        #else
        return 1
        #endif
    }

    // MARK: - Spacing
    /// Standard content padding
    static var contentPadding: CGFloat {
        #if os(tvOS)
        return 48
        #else
        return AppSpacing.md
        #endif
    }

    /// Grid spacing
    static var gridSpacing: CGFloat {
        #if os(tvOS)
        return 32
        #else
        return AppSpacing.md
        #endif
    }

    /// Section spacing
    static var sectionSpacing: CGFloat {
        #if os(tvOS)
        return 48
        #else
        return AppSpacing.xl
        #endif
    }

    // MARK: - Card Sizes
    /// Card padding
    static var cardPadding: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return AppSpacing.sm
        #endif
    }

    /// Hero section height
    static var heroHeight: CGFloat {
        #if os(tvOS)
        return 500
        #else
        return 320
        #endif
    }

    // MARK: - Focus Effects (tvOS only)
    /// Scale effect when focused (reduced for better performance)
    static var focusScale: CGFloat {
        #if os(tvOS)
        return 1.05
        #else
        return 1.0
        #endif
    }

    /// Shadow radius when focused (reduced for better performance)
    static var focusShadowRadius: CGFloat {
        #if os(tvOS)
        return 12  // Reduced from 20 for better performance
        #else
        return 0
        #endif
    }

    /// Animation duration for focus transitions (longer for smoother tvOS perception)
    static var focusAnimationDuration: Double {
        #if os(tvOS)
        return 0.35  // Longer duration feels smoother on tvOS
        #else
        return 0.2
        #endif
    }

    /// Simplified shadow for focused state (less GPU intensive)
    static var focusShadowOpacity: Double {
        #if os(tvOS)
        return 0.25  // Reduced from 0.4 for better performance
        #else
        return 0.0
        #endif
    }
}

// MARK: - Corner Radius System

struct AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let pill: CGFloat = 9999

    // MARK: - Semantic Radius
    static let button: CGFloat = md
    static let card: CGFloat = lg
    static let modal: CGFloat = xl
    static let thumbnail: CGFloat = sm
}

// MARK: - Shadow Styles

struct AppShadow {
    static let none = Shadow(color: .clear, radius: 0, x: 0, y: 0)

    static let sm = Shadow(
        color: Color.black.opacity(0.1),
        radius: 2,
        x: 0,
        y: 1
    )

    static let md = Shadow(
        color: Color.black.opacity(0.15),
        radius: 4,
        x: 0,
        y: 2
    )

    static let lg = Shadow(
        color: Color.black.opacity(0.2),
        radius: 8,
        x: 0,
        y: 4
    )

    static let xl = Shadow(
        color: Color.black.opacity(0.25),
        radius: 16,
        x: 0,
        y: 8
    )

    static let glow = Shadow(
        color: ColorPalette.primary.opacity(0.4),
        radius: 12,
        x: 0,
        y: 0
    )

    static let glowSecondary = Shadow(
        color: ColorPalette.secondary.opacity(0.4),
        radius: 12,
        x: 0,
        y: 0
    )
}

// MARK: - App Theme Environment

struct AppTheme {
    var colorScheme: ColorScheme

    // MARK: - Adaptive Colors
    var background: Color {
        colorScheme == .dark ? ColorPalette.backgroundDark : ColorPalette.backgroundLight
    }

    var surface: Color {
        colorScheme == .dark ? ColorPalette.surfaceDark : ColorPalette.surfaceLight
    }

    var cardBackground: Color {
        colorScheme == .dark ? ColorPalette.cardBackgroundDark : ColorPalette.cardBackgroundLight
    }

    var cardBackgroundElevated: Color {
        colorScheme == .dark ? ColorPalette.cardBackgroundElevatedDark : ColorPalette.cardBackgroundElevatedLight
    }

    var textPrimary: Color {
        colorScheme == .dark ? ColorPalette.textPrimaryDark : ColorPalette.textPrimaryLight
    }

    var textSecondary: Color {
        colorScheme == .dark ? ColorPalette.textSecondaryDark : ColorPalette.textSecondaryLight
    }

    var textMuted: Color {
        colorScheme == .dark ? ColorPalette.textMutedDark : ColorPalette.textMutedLight
    }

    var textDisabled: Color {
        colorScheme == .dark ? ColorPalette.textDisabledDark : ColorPalette.textDisabledLight
    }

    var divider: Color {
        colorScheme == .dark ? ColorPalette.divider : ColorPalette.dividerLight
    }

    var overlay: Color {
        colorScheme == .dark ? ColorPalette.overlay : ColorPalette.overlayLight
    }
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme(colorScheme: .dark)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Color Extension (Hex Support)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Shadow Extension

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func appShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    let elevation: Int
    let padding: CGFloat

    init(elevation: Int = 1, padding: CGFloat = AppSpacing.cardPadding) {
        self.elevation = elevation
        self.padding = padding
    }

    func body(content: Content) -> some View {
        let theme = AppTheme(colorScheme: colorScheme)

        content
            .padding(padding)
            .background(theme.cardBackground)
            .cornerRadius(AppRadius.card)
            .appShadow(shadowForElevation(elevation))
    }

    private func shadowForElevation(_ level: Int) -> Shadow {
        switch level {
        case 0: return AppShadow.none
        case 1: return AppShadow.sm
        case 2: return AppShadow.md
        case 3: return AppShadow.lg
        default: return AppShadow.xl
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    let isDestructive: Bool

    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button())
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button)
                    .fill(isDestructive ? ColorPalette.error : ColorPalette.primary)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let theme = AppTheme(colorScheme: colorScheme)

        configuration.label
            .font(AppTypography.button())
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.button)
                            .stroke(theme.divider, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle(elevation: Int = 1, padding: CGFloat = AppSpacing.cardPadding) -> some View {
        self.modifier(CardModifier(elevation: elevation, padding: padding))
    }

    func primaryButtonStyle(isDestructive: Bool = false) -> some View {
        self.buttonStyle(PrimaryButtonStyle(isDestructive: isDestructive))
    }

    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }

    /// Cross-platform navigation bar title display mode modifier
    /// On tvOS, this is a no-op since navigationBarTitleDisplayMode isn't available
    @ViewBuilder
    func navBarTitleDisplayMode(_ mode: NavBarTitleDisplayMode) -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(mode.nativeMode)
        #endif
    }
}

/// Cross-platform wrapper for NavigationBarItem.TitleDisplayMode
enum NavBarTitleDisplayMode {
    case automatic
    case inline
    case large

    #if !os(tvOS)
    var nativeMode: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .automatic: return .automatic
        case .inline: return .inline
        case .large: return .large
        }
    }
    #endif
}

// MARK: - tvOS Focus Style Modifier

/// A view modifier that adds focus effects for tvOS
/// Optimized for performance with reduced shadow complexity and longer animation duration
struct TVFocusStyle: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    let scaleEffect: CGFloat
    let shadowRadius: CGFloat

    init(scaleEffect: CGFloat = TVSizing.focusScale, shadowRadius: CGFloat = TVSizing.focusShadowRadius) {
        self.scaleEffect = scaleEffect
        self.shadowRadius = shadowRadius
    }

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .scaleEffect(isFocused ? scaleEffect : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.primary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? shadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        #else
        content
        #endif
    }
}

extension View {
    /// Adds tvOS focus styling (scale + shadow on focus)
    func tvFocusStyle(scale: CGFloat = TVSizing.focusScale, shadowRadius: CGFloat = TVSizing.focusShadowRadius) -> some View {
        self.modifier(TVFocusStyle(scaleEffect: scale, shadowRadius: shadowRadius))
    }
}

// MARK: - tvOS Card Button Style

/// A button style optimized for tvOS with focus effects
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            #if os(tvOS)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            #else
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            #endif
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
