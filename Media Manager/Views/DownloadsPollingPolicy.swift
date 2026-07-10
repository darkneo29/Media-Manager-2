import SwiftUI

enum DownloadsPollingPolicy {
    static let refreshIntervalSeconds: TimeInterval = 5

    static func shouldPoll(
        isActiveTab: Bool,
        isViewVisible: Bool,
        isViewingActiveQueue: Bool,
        scenePhase: ScenePhase,
        isSabConfigured: Bool
    ) -> Bool {
        isActiveTab &&
            isViewVisible &&
            isViewingActiveQueue &&
            scenePhase == .active &&
            isSabConfigured
    }
}
