import SwiftUI

struct AppLaunchOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.06)
                .ignoresSafeArea()

            Image("LaunchImage")
                .resizable()
                #if os(tvOS)
                // Keep the same iOS artwork fully visible on a landscape TV.
                .scaledToFit()
                #else
                .scaledToFill()
                #endif
                .ignoresSafeArea()
        }
    }
}

#Preview {
    AppLaunchOverlay()
}
