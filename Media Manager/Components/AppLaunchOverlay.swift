import SwiftUI

struct AppLaunchOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.06)
                .ignoresSafeArea()

            Image("LaunchImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    AppLaunchOverlay()
}
