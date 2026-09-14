import SwiftUI

/// Standalone tabs own a stack. Screens pushed from More reuse its stack and path.
struct AppNavigationContainer<Content: View>: View {
    var isEmbedded = false
    var path: Binding<NavigationPath>? = nil
    @ViewBuilder var content: () -> Content
    @State private var localPath = NavigationPath()

    var body: some View {
        if isEmbedded { content() }
        else { NavigationStack(path: path ?? $localPath) { content() } }
    }
}
