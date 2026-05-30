import SwiftUI

struct ContentView: View {
    @State private var showsLaunchOverlay = true

    var body: some View {
        ZStack {
            MainTabView()

            if showsLaunchOverlay {
                AppLaunchOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showsLaunchOverlay else { return }

            try? await Task.sleep(for: .milliseconds(900))

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    showsLaunchOverlay = false
                }
            }
        }
    }
}
