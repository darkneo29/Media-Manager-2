import SwiftUI

enum DownloadsPollingPolicy {
    static func shouldPoll(isActiveTab: Bool, scenePhase: ScenePhase, isSabConfigured: Bool) -> Bool {
        isActiveTab && scenePhase == .active && isSabConfigured
    }
}
