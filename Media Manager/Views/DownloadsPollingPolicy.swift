import SwiftUI

enum DownloadsPollingPolicy {
    static let refreshIntervalSeconds: TimeInterval = 5

    static func shouldPoll(
        isViewVisible: Bool,
        isViewingActiveQueue: Bool,
        scenePhase: ScenePhase,
        isSabConfigured: Bool
    ) -> Bool {
        isViewVisible &&
            isViewingActiveQueue &&
            scenePhase == .active &&
            isSabConfigured
    }
}
