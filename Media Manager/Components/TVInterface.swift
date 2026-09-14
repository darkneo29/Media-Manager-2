import SwiftUI

#if os(tvOS)
/// A consistent remote-sized action with one focus treatment.
struct TVInterfaceButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 25, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 24)
            .frame(minHeight: 64)
            .foregroundStyle(isFocused ? ColorPalette.backgroundDark : .white)
            .background(isFocused ? .white : (prominent ? ColorPalette.primary : ColorPalette.cardBackgroundDark), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFocused ? ColorPalette.secondary : ColorPalette.divider, lineWidth: isFocused ? 3 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : (isFocused ? 1.03 : 1)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

/// Explicit menu labels keep the selected value readable on the TV canvas.
struct TVSelectionMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    if value == selection {
                        Label(label(value), systemImage: "checkmark")
                    } else {
                        Text(label(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(label(selection))
                Image(systemName: "chevron.down")
            }
        }
        .buttonStyle(TVInterfaceButtonStyle())
        .disabled(options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

struct TVBooleanButton: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(isOn ? "On" : "Off", systemImage: isOn ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(TVInterfaceButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Keep library browsing visible until someone explicitly chooses to search.
struct TVLibrarySearchButton: View {
    @Binding var text: String
    let title: String
    @State private var isPresented = false
    @State private var draft = ""

    var body: some View {
        Button {
            draft = text
            isPresented = true
        } label: {
            Label(text.isEmpty ? "Search" : "Search: \(text)", systemImage: "magnifyingglass")
                .frame(maxWidth: 360, alignment: .leading)
        }
        .buttonStyle(TVInterfaceButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(text.isEmpty ? "All titles" : text)
        .alert(title, isPresented: $isPresented) {
            TextField("Title", text: $draft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Search") { text = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !text.isEmpty {
                Button("Clear Search") { text = "" }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

/// Secondary add options live in their own scrollable sheet, leaving room for results.
struct TVAddOptionsSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Options").font(AppTypography.title1())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(TVInterfaceButtonStyle(prominent: true))
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 32)
            ScrollView {
                content()
                    .frame(maxWidth: 1200)
                    .padding(.vertical, 32)
            }
        }
        .background(ColorPalette.backgroundDark.ignoresSafeArea())
    }
}
#endif

extension View {
    /// TV review forms need a full canvas; mobile retains its standard sheet.
    @ViewBuilder
    func mediaReviewSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    @ViewBuilder
    func mediaReviewSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}
