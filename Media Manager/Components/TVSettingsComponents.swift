import SwiftUI

#if os(tvOS)

// MARK: - Text Field Card

/// A focusable text field card for tvOS settings
struct TVTextFieldCard: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var icon: String = "text.cursor"
    var isSecure: Bool = false

    @Environment(\.isFocused) private var isFocused
    @State private var showingInputSheet = false
    @State private var tempText = ""

    var body: some View {
        Button {
            tempText = text
            showingInputSheet = true
        } label: {
            HStack(spacing: AppSpacing.lg) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 44)

                // Content
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(label)
                        .font(.system(size: 22))
                        .foregroundColor(ColorPalette.textSecondaryDark)

                    if isSecure && !text.isEmpty {
                        Text(String(repeating: "•", count: min(text.count, 20)))
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(ColorPalette.textPrimaryDark)
                    } else {
                        Text(text.isEmpty ? placeholder : text)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(text.isEmpty ? ColorPalette.textMutedDark : ColorPalette.textPrimaryDark)
                    }
                }

                Spacer()

                // Edit indicator
                Image(systemName: "pencil")
                    .font(.system(size: 24))
                    .foregroundColor(ColorPalette.textMutedDark)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
            )
            .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        }
        .buttonStyle(.plain)
        .alert(label, isPresented: $showingInputSheet) {
            if isSecure {
                SecureField(placeholder, text: $tempText)
            } else {
                TextField(placeholder, text: $tempText)
            }
            Button("Cancel", role: .cancel) {
                tempText = ""
            }
            Button("Save") {
                text = tempText
                tempText = ""
            }
        } message: {
            Text("Enter your \(label.lowercased())")
        }
    }
}

// MARK: - Action Button

/// A large action button for tvOS
struct TVActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 28, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? Color.white.opacity(0.5) : Color.clear, lineWidth: 4)
            )
            .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
            .shadow(
                color: isFocused ? color.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Status Message

enum TVStatusType {
    case success
    case error
    case info
    case warning

    var color: Color {
        switch self {
        case .success: return ColorPalette.success
        case .error: return ColorPalette.error
        case .info: return ColorPalette.info
        case .warning: return ColorPalette.warning
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }
}

struct TVStatusMessage: View {
    let message: String
    let type: TVStatusType

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: type.icon)
                .font(.system(size: 28))
                .foregroundColor(type.color)

            Text(message)
                .font(.system(size: 24))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(type.color.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(type.color.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Action Card

/// A focusable action card for tvOS
struct TVActionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 70, height: 70)

                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(iconColor)
                }

                // Text
                VStack(spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
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

// MARK: - Help Card

/// A card showing API key help instructions for tvOS
struct TVHelpCard: View {
    let service: APIKeyGuideService

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(ColorPalette.info)

                Text("How to get your API key")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)
            }

            // Steps
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(service.steps) { step in
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Text("\(step.number)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ColorPalette.backgroundDark)
                            .frame(width: 32, height: 32)
                            .background(service.iconColor)
                            .clipShape(Circle())

                        Text(step.text)
                            .font(.system(size: 22))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                }
            }

            // Notes
            if !service.notes.isEmpty {
                Divider()
                    .background(ColorPalette.divider)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(service.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Text("•")
                                .foregroundColor(ColorPalette.textMutedDark)
                            Text(note)
                                .font(.system(size: 20))
                                .foregroundColor(ColorPalette.textMutedDark)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(ColorPalette.cardBackgroundDark)
        )
    }
}

// MARK: - Logs View

/// Full-screen logs view for tvOS
struct TVLogsView: View {
    let title: String
    let logs: [LogEntry]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: TVSizing.sectionSpacing) {
                // Header
                HStack {
                    Text(title)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    HStack(spacing: AppSpacing.lg) {
                        Button(action: onRefresh) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(ColorPalette.secondary)
                        }

                        Button(action: onDismiss) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "xmark")
                                Text("Close")
                            }
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        }
                    }
                }
                .padding(.horizontal, TVSizing.contentPadding)

                // Content
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(2)
                    Text("Loading logs...")
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                        .padding(.top, AppSpacing.lg)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    TVStatusMessage(message: error, type: .error)
                        .padding(.horizontal, TVSizing.contentPadding)
                    Spacer()
                } else if logs.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 60))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No logs available")
                            .font(.system(size: 28))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(logs) { log in
                                TVLogEntryCard(log: log)
                            }
                        }
                        .padding(.horizontal, TVSizing.contentPadding)
                        .padding(.bottom, TVSizing.sectionSpacing)
                    }
                }
            }
            .padding(.top, TVSizing.sectionSpacing)
        }
    }
}

/// Individual log entry card for tvOS
struct TVLogEntryCard: View {
    let log: LogEntry

    var levelColor: Color {
        switch log.level.lowercased() {
        case "error", "fatal": return ColorPalette.error
        case "warn", "warning": return ColorPalette.warning
        case "info": return ColorPalette.info
        case "debug": return ColorPalette.textMutedDark
        default: return ColorPalette.textSecondaryDark
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header row
            HStack {
                // Level badge
                Text(log.level.uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(levelColor)
                    .cornerRadius(AppRadius.sm)

                // Timestamp
                Text(formatDate(log.time))
                    .font(.system(size: 20))
                    .foregroundColor(ColorPalette.textMutedDark)

                Spacer()

                // Logger
                Text(log.logger ?? "")
                    .font(.system(size: 18))
                    .foregroundColor(ColorPalette.textMutedDark)
            }

            // Message
            Text(log.message)
                .font(.system(size: 22))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .lineLimit(3)

            // Exception if present
            if let exception = log.exception, !exception.isEmpty {
                Text(exception)
                    .font(.system(size: 18))
                    .foregroundColor(ColorPalette.error)
                    .lineLimit(2)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(ColorPalette.cardBackgroundDark)
        )
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm:ss"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Backups View

/// Full-screen backups view for tvOS
struct TVBackupsView: View {
    let title: String
    let backups: [ServerBackup]
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onRestore: (ServerBackup) -> Void
    let onDismiss: () -> Void

    @State private var selectedBackup: ServerBackup?
    @State private var showingConfirmation = false

    var body: some View {
        ZStack {
            ColorPalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: TVSizing.sectionSpacing) {
                // Header
                HStack {
                    Text(title)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Spacer()

                    HStack(spacing: AppSpacing.lg) {
                        Button(action: onRefresh) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(ColorPalette.secondary)
                        }

                        Button(action: onDismiss) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "xmark")
                                Text("Close")
                            }
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                        }
                    }
                }
                .padding(.horizontal, TVSizing.contentPadding)

                // Content
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(2)
                    Text("Loading backups...")
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                        .padding(.top, AppSpacing.lg)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    TVStatusMessage(message: error, type: .error)
                        .padding(.horizontal, TVSizing.contentPadding)
                    Spacer()
                } else if backups.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 60))
                            .foregroundColor(ColorPalette.textMutedDark)
                        Text("No backups available")
                            .font(.system(size: 28))
                            .foregroundColor(ColorPalette.textSecondaryDark)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.md) {
                            ForEach(backups) { backup in
                                TVBackupCard(backup: backup) {
                                    selectedBackup = backup
                                    showingConfirmation = true
                                }
                            }
                        }
                        .padding(.horizontal, TVSizing.contentPadding)
                        .padding(.bottom, TVSizing.sectionSpacing)
                    }
                }
            }
            .padding(.top, TVSizing.sectionSpacing)
        }
        .alert("Restore Backup?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedBackup = nil
            }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    onRestore(backup)
                    onDismiss()
                }
            }
        } message: {
            if let backup = selectedBackup {
                Text("This will restore \(backup.name). The server will restart after the restore completes.")
            }
        }
    }
}

/// Individual backup card for tvOS
struct TVBackupCard: View {
    let backup: ServerBackup
    let onRestore: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: AppSpacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(ColorPalette.info.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 28))
                        .foregroundColor(ColorPalette.info)
                }

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(backup.name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Text(formatDate(backup.time))
                        .font(.system(size: 20))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Spacer()

                // Restore indicator
                HStack(spacing: AppSpacing.sm) {
                    Text("Restore")
                        .font(.system(size: 22))
                        .foregroundColor(ColorPalette.secondary)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 22))
                        .foregroundColor(ColorPalette.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
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

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Toggle Card

/// A focusable toggle card for tvOS settings
struct TVToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(ColorPalette.textPrimaryDark)

                    Text(subtitle)
                        .font(.system(size: 22))
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }

                Spacer()

                // Toggle indicator
                ZStack {
                    Capsule()
                        .fill(isOn ? ColorPalette.secondary : ColorPalette.textMutedDark.opacity(0.3))
                        .frame(width: 70, height: 40)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .offset(x: isOn ? 14 : -14)
                        .animation(.easeInOut(duration: 0.2), value: isOn)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
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

// MARK: - Picker Card

/// A focusable picker card for tvOS settings
struct TVPickerCard: View {
    let title: String
    @Binding var selection: String
    let options: [(value: String, label: String)]

    @Environment(\.isFocused) private var isFocused
    @State private var currentIndex: Int = 0

    var body: some View {
        Button {
            // Cycle through options
            currentIndex = (currentIndex + 1) % options.count
            selection = options[currentIndex].value
        } label: {
            HStack(spacing: AppSpacing.lg) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(ColorPalette.textPrimaryDark)

                Spacer()

                HStack(spacing: AppSpacing.sm) {
                    Text(currentLabel)
                        .font(.system(size: 24))
                        .foregroundColor(ColorPalette.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 20))
                        .foregroundColor(ColorPalette.textMutedDark)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(ColorPalette.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isFocused ? ColorPalette.secondary : Color.clear, lineWidth: 4)
            )
            .scaleEffect(isFocused ? TVSizing.focusScale : 1.0)
            .shadow(
                color: isFocused ? ColorPalette.secondary.opacity(TVSizing.focusShadowOpacity) : Color.clear,
                radius: isFocused ? TVSizing.focusShadowRadius : 0
            )
            .animation(.easeInOut(duration: TVSizing.focusAnimationDuration), value: isFocused)
        }
        .buttonStyle(.plain)
        .onAppear {
            // Set initial index based on selection
            if let index = options.firstIndex(where: { $0.value == selection }) {
                currentIndex = index
            }
        }
        .onChange(of: selection) { _, newValue in
            if let index = options.firstIndex(where: { $0.value == newValue }) {
                currentIndex = index
            }
        }
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? selection
    }
}

// MARK: - Requirement Row

/// A requirement row for tvOS
struct TVRequirementRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 32)

            Text(text)
                .font(.system(size: 24))
                .foregroundColor(ColorPalette.textSecondaryDark)
        }
    }
}

#endif
