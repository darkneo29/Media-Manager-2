//
//  Media_ManagerApp.swift
//  Media Manager
//
//

import SwiftUI

@main
struct Media_ManagerApp: App {
    @State private var deepLinkHandler = DeepLinkHandler.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(deepLinkHandler)
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
        }
    }
}
