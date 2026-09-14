import SwiftUI

// MARK: - Lazy View Wrapper for tvOS Tab Performance

/// A view wrapper that defers content creation until the view appears
/// This reduces initial load time for TabView on tvOS
struct LazyView<Content: View>: View {
    let build: () -> Content
    @State private var hasAppeared = false

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        Group {
            if hasAppeared {
                build()
            } else {
                Color.clear
                    .onAppear {
                        hasAppeared = true
                    }
            }
        }
    }
}

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DeepLinkHandler.self) private var deepLinkHandler
    @ObservedObject private var libraryState = LibraryStateManager.shared
    @State private var selectedTab: Int? = 0
    @State private var moreNavigationPath = NavigationPath()

    // Deep link navigation state - passed to child views
    @State private var deepLinkMovieId: Int?
    @State private var deepLinkTVShowId: Int?

    init() {
        #if !os(tvOS)
        // Configure tab bar appearance for dark theme
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(ColorPalette.surfaceDark)

        // Unselected items
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(ColorPalette.textMutedDark)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(ColorPalette.textMutedDark)
        ]

        // Selected items
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(ColorPalette.secondary)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(ColorPalette.secondary)
        ]

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Configure navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(ColorPalette.backgroundDark)
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(ColorPalette.primary)
        ]
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(ColorPalette.primary)
        ]

        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(ColorPalette.secondary)
        #endif
    }

    var body: some View {
        Group {
            #if os(tvOS)
            // tvOS: Tab bar navigation (appears at top)
            tvOSLayout
            #else
            if horizontalSizeClass == .regular {
                // iPad: Sidebar navigation
                iPadLayout
            } else {
                // iPhone: Tab bar navigation
                iPhoneLayout
            }
            #endif
        }
        .onChange(of: deepLinkHandler.pendingDestination) { _, destination in
            handleDeepLink(destination)
        }
        .onAppear {
            // Handle any pending deep link on appear
            if let destination = deepLinkHandler.pendingDestination {
                handleDeepLink(destination)
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ destination: DeepLinkDestination?) {
        guard let destination = destination else { return }

        switch destination {
        case .movie(let id):
            // Switch to Movies tab and trigger navigation
            selectedTab = 2
            deepLinkMovieId = id
            deepLinkTVShowId = nil
        case .tvShow(let id):
            // Switch to TV Shows tab and trigger navigation
            selectedTab = 3
            deepLinkTVShowId = id
            deepLinkMovieId = nil
        case .calendar:
            selectedTab = 5
            moreNavigationPath = NavigationPath([MoreDestination.calendar])
        case .downloads:
            selectedTab = 4
            moreNavigationPath = NavigationPath([MoreDestination.downloads])
        case .settings:
            selectedTab = 7
            moreNavigationPath = NavigationPath([MoreDestination.settings])
        }

        // Clear the pending destination after handling
        deepLinkHandler.clearPendingDestination()
    }

    // MARK: - iPad Layout (Sidebar Navigation)

    #if !os(tvOS)
    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    sidebarItem(title: "Home", icon: "house.fill", tag: 0)
                    sidebarItem(title: "Discover", icon: "sparkles", tag: 1)
                }

                Section("Library") {
                    sidebarItem(title: "Movies", icon: "film.fill", tag: 2)
                    sidebarItem(title: "TV Shows", icon: "tv.fill", tag: 3)
                    sidebarItem(title: "Downloads", icon: "arrow.down.circle.fill", tag: 4)
                    sidebarItem(title: "Calendar", icon: "calendar", tag: 5)
                }

                Section("Server") {
                    sidebarItem(title: "Unraid", icon: "server.rack", tag: 6)
                }

                Section {
                    sidebarItem(title: "Settings", icon: "gear", tag: 7)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Media Manager")
            .scrollContentBackground(.hidden)
            .background(ColorPalette.backgroundDark)
            .contentMargins(.top, AppSpacing.xs, for: .scrollContent)
        } detail: {
            detailView(for: selectedTab ?? 0)
        }
        .tint(ColorPalette.secondary)
    }

    private func sidebarItem(title: String, icon: String, tag: Int) -> some View {
        Label(title, systemImage: icon)
            .tag(tag)
            .listRowBackground(
                selectedTab == tag
                    ? ColorPalette.primary.opacity(0.2)
                    : Color.clear
            )
    }
    #endif

    @ViewBuilder
    private func detailView(for tab: Int) -> some View {
        switch tab {
        case 0:
            DashboardView()
        case 1:
            DiscoverView()
        case 2:
            MovieListView(deepLinkMovieId: $deepLinkMovieId)
        case 3:
            TVShowListView(deepLinkTVShowId: $deepLinkTVShowId)
        case 4:
            DownloadsView()
        case 5:
            CalendarView()
        case 6:
            ServerView()
        case 7:
            SettingsView()
        default:
            DashboardView()
        }
    }

    // MARK: - iPhone Layout (Tab Bar Navigation)

    private var selectedTabBinding: Binding<Int> {
        Binding(
            get: { selectedTab ?? 0 },
            set: { selectedTab = $0 }
        )
    }

    #if !os(tvOS)
    private var iPhoneLayout: some View {
        TabView(selection: phoneTabSelection) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
                .tag(1)

            MovieListView(deepLinkMovieId: $deepLinkMovieId)
                .tabItem {
                    Label("Movies", systemImage: "film.fill")
                }
                .tag(2)

            TVShowListView(deepLinkTVShowId: $deepLinkTVShowId)
                .tabItem {
                    Label("TV Shows", systemImage: "tv.fill")
                }
                .tag(3)

            moreNavigation
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(8)
        }
        .tint(ColorPalette.secondary)
        .onAppear {
            // Preserve the selected destination when an iPad enters compact width.
            if let destination = MoreDestination(rawValue: selectedTab ?? 0), moreNavigationPath.isEmpty {
                moreNavigationPath.append(destination)
            }
        }
    }

    private var phoneTabSelection: Binding<Int> {
        Binding(get: { (0...3).contains(selectedTab ?? 0) ? (selectedTab ?? 0) : 8 },
                set: { selectedTab = $0 })
    }

    private var moreNavigation: some View {
        NavigationStack(path: $moreNavigationPath) {
            List(MoreDestination.allCases) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.icon)
                }
                .accessibilityIdentifier("more.\(destination.rawValue)")
                .listRowBackground(ColorPalette.cardBackgroundDark)
            }
            .scrollContentBackground(.hidden)
            .background(ColorPalette.backgroundDark)
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                moreDestination(destination)
                    .onAppear { selectedTab = destination.rawValue }
            }
        }
    }

    @ViewBuilder
    private func moreDestination(_ destination: MoreDestination) -> some View {
        switch destination {
        case .downloads: DownloadsView(isEmbedded: true)
        case .calendar: CalendarView(isEmbedded: true, sharedNavigationPath: $moreNavigationPath)
        case .unraid: ServerView(isEmbedded: true)
        case .settings: SettingsView(isEmbedded: true, sharedNavigationPath: $moreNavigationPath)
        }
    }

    #endif

    // MARK: - tvOS Layout (Top Tab Bar Navigation)
    // Uses LazyView to defer tab content creation for better initial load performance

    #if os(tvOS)
    private var tvOSLayout: some View {
        TabView(selection: selectedTabBinding) {
            // Dashboard loads immediately as it's the default tab
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Other tabs use LazyView to defer content creation until selected
            LazyView(DiscoverView())
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
                .tag(1)

            LazyView(MovieListView(deepLinkMovieId: $deepLinkMovieId))
                .tabItem {
                    Label("Movies", systemImage: "film.fill")
                }
                .tag(2)

            LazyView(TVShowListView(deepLinkTVShowId: $deepLinkTVShowId))
                .tabItem {
                    Label("TV Shows", systemImage: "tv.fill")
                }
                .tag(3)

            LazyView(DownloadsView())
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle.fill")
                }
                .tag(4)

            LazyView(CalendarView())
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(5)

            LazyView(ServerView())
                .tabItem {
                    Label("Unraid", systemImage: "server.rack")
                }
                .tag(6)

            LazyView(SettingsView())
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(7)
        }
    }
    #endif
}

#Preview {
    MainTabView()
        .preferredColorScheme(.dark)
        .environment(DeepLinkHandler.shared)
}

private enum MoreDestination: Int, CaseIterable, Identifiable, Hashable {
    case downloads = 4, calendar = 5, unraid = 6, settings = 7
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .calendar: return "Calendar"
        case .unraid: return "Unraid"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle.fill"
        case .calendar: return "calendar"
        case .unraid: return "server.rack"
        case .settings: return "gear"
        }
    }
}
