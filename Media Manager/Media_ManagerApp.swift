//
//  Media_ManagerApp.swift
//  Media Manager
//
//

import SwiftUI
import AppIntents

@main
struct Media_ManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var deepLinkHandler = DeepLinkHandler.shared

    init() {
        #if DEBUG && os(iOS)
        MediaIntelligenceFixtures.installIfRequested()
        #endif
        #if DEBUG
        UnraidIntegrationFixtures.installIfRequested()
        #endif
        #if DEBUG && os(tvOS)
        TVDesignFixtures.installIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if UnraidIntegrationFixtures.enabled {
                    if ProcessInfo.processInfo.arguments.contains("--unraid-dashboard") { DashboardView() }
                    else { ServerView() }
                }
                else { ContentView() }
                #else
                ContentView()
                #endif
            }
                .preferredColorScheme(.dark)
                .environment(deepLinkHandler)
                .task {
                    #if os(iOS)
                    WatchSnapshotService.shared.start()
                    #endif
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    MediaManagerShortcuts.updateAppShortcutParameters()
                    // Start sync even when Settings has never been opened.
                    while !Task.isCancelled {
                        await iCloudSyncService.shared.synchronize()
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    }
                }
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
        }
    }
}
