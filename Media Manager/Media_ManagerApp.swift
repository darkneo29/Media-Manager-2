//
//  Media_ManagerApp.swift
//  Media Manager
//
//

import SwiftUI

@main
struct Media_ManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var deepLinkHandler = DeepLinkHandler.shared

    init() {
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
                if UnraidIntegrationFixtures.enabled { ServerView() }
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
