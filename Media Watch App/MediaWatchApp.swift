import SwiftUI

@main
struct MediaWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .preferredColorScheme(.dark)
        }
    }
}
