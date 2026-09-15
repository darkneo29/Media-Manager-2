import SwiftUI

struct WatchDashboardView: View {
    @StateObject private var store = WatchDashboardStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if !store.hasSnapshot {
                    Section {
                        Label("Connect your iPhone", systemImage: "iphone")
                            .font(.headline)
                        Text("Open Media Manager on iPhone to sync your library and services.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink {
                        WatchSearchView(store: store)
                    } label: {
                        Label("Find & Add", systemImage: "magnifyingglass")
                            .font(.headline)
                            .foregroundStyle(WatchTheme.accent)
                            .padding(.vertical, 6)
                    }
                    NavigationLink {
                        WatchDownloadsView(store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Downloads", systemImage: "arrow.down.circle.fill")
                            Text(store.snapshot.downloads.statusText)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        List {
                            if store.snapshot.upcoming.isEmpty {
                                EmptyStateRow(icon: "calendar", title: "No upcoming releases", subtitle: "Your enabled release filters on iPhone apply here too.")
                            }
                            ForEach(store.snapshot.upcoming) { item in
                                UpcomingRow(item: item)
                            }
                        }.navigationTitle("Upcoming")
                    } label: {
                        Label("Upcoming", systemImage: "calendar")
                    }
                }
                if #available(watchOS 27.0, *) {
                    Section("Library Summary") {
                        Button("Summarize", systemImage: "sparkles") { store.requestLibrarySummary() }
                            .disabled(store.isSummarizing)
                        if store.isSummarizing { ProgressView("Asking iPhone…") }
                        if !store.librarySummary.isEmpty { Text(store.librarySummary).font(.callout) }
                    }
                }
                Section("Library") {
                    HStack(spacing: 6) {
                        MetricTile(value: store.hasSnapshot ? "\(store.snapshot.library.movieCount)" : "—", label: "Movies", icon: "film.fill")
                        MetricTile(value: store.hasSnapshot ? "\(store.snapshot.library.showCount)" : "—", label: "Shows", icon: "tv.fill")
                    }.listRowBackground(Color.clear)
                    NavigationLink {
                        List {
                            ForEach(store.snapshot.services) { ServiceRow(service: $0) }
                            Text("Configure services in the iPhone app.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.navigationTitle("Services")
                    } label: {
                        Label("Services", systemImage: "server.rack")
                    }
                }
                Section {
                    Text(store.connectionStatus).font(.caption2)
                    if store.hasSnapshot {
                        Text("Updated \(store.snapshot.generatedAt, style: .relative) ago")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Time since last sync")
                    }
                    Button(action: { store.requestRefresh() }) {
                        Label(store.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                    }.disabled(store.isRefreshing)
                }
            }
            .navigationTitle("Media")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.requestRefresh()
        }
    }
}

private struct WatchSearchView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        List {
            Section {
                Picker("Search for", selection: $store.searchKind) {
                    ForEach(WatchMediaKind.allCases) { Text($0.title).tag($0) }
                }.disabled(store.isSearching || store.addingResultId != nil)
                Button {
                    let kind = store.searchKind
                    WatchVoiceInput.requestTitle { phrase in
                        guard let phrase else { return }
                        store.searchMedia(kind: kind, query: phrase)
                    }
                } label: {
                    Label("Say a title", systemImage: "mic.fill")
                }.tint(WatchTheme.accent)
                    .disabled(store.isSearching || store.addingResultId != nil)
                TextField("Type a title", text: $store.searchQuery)
                    .submitLabel(.search)
                    .onSubmit { search() }
                    .disabled(store.isSearching || store.addingResultId != nil)
                Button(action: search) {
                    if store.isSearching { ProgressView("Searching…") }
                    else { Label("Search", systemImage: "magnifyingglass") }
                }.disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearching || store.addingResultId != nil)
            }
            if !store.mediaActionStatus.isEmpty {
                Text(store.mediaActionStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(store.searchResults) { result in
                    NavigationLink {
                        WatchMediaDetailView(store: store, result: result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.displayTitle).font(.headline)
                            Text(store.isAdded(result) ? "In library" : result.subtitle)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Find & Add")
    }

    private func search() {
        store.searchMedia(kind: store.searchKind, query: store.searchQuery)
    }
}

private struct WatchMediaDetailView: View {
    @ObservedObject var store: WatchDashboardStore
    let result: WatchMediaSearchResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: result.kind == .movie ? "film.fill" : "tv.fill")
                    .font(.largeTitle).foregroundStyle(WatchTheme.accent)
                Text(result.displayTitle).font(.title3.bold())
                Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                Button { store.addMedia(result) } label: {
                    if store.addingResultId == result.id { ProgressView("Adding…") }
                    else { Label(store.isAdded(result) ? "In library" : "Add to library", systemImage: store.isAdded(result) ? "checkmark" : "plus") }
                }
                .buttonStyle(.borderedProminent).tint(WatchTheme.success)
                .disabled(store.isAdded(result) || store.addingResultId != nil || store.isSearching)
                if !store.mediaActionStatus.isEmpty {
                    Text(store.mediaActionStatus).font(.caption)
                }
                Text("Uses your saved add settings on iPhone, including automatic search.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview).font(.body)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
        }.navigationTitle(result.kind.title)
    }
}

private struct WatchDownloadsView: View {
    @ObservedObject var store: WatchDashboardStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if !store.snapshot.downloads.isConfigured {
                EmptyStateRow(icon: "iphone", title: "Set up SABnzbd", subtitle: "Configure downloads in Media Manager on iPhone.")
            } else {
                Section {
                    Text(store.snapshot.downloads.statusText).font(.headline)
                    Text(store.snapshot.downloads.speedBytesPerSecond.watchFormattedBytesPerSecond)
                        .font(.caption).foregroundStyle(.secondary)
                    Button(action: store.toggleDownloads) {
                        Label(store.isControllingDownloads ? "Updating…" : (store.snapshot.downloads.isPaused ? "Resume queue" : "Pause queue"), systemImage: store.snapshot.downloads.isPaused ? "play.fill" : "pause.fill")
                    }.disabled(store.isControllingDownloads || store.snapshot.downloads.errorMessage != nil)
                    if !store.downloadActionStatus.isEmpty {
                        Text(store.downloadActionStatus).font(.caption)
                    }
                }
                Section("Queue") {
                    if store.snapshot.downloads.items.isEmpty && store.snapshot.downloads.errorMessage == nil {
                        Text("No downloads queued").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.snapshot.downloads.items) { DownloadRow(item: $0) }
                }
            }
            Button("Refresh", action: { store.requestRefresh() }).disabled(store.isRefreshing)
        }
        .navigationTitle("Downloads")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.requestRefresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard store.snapshot.downloads.isConfigured else { continue }
                store.requestRefresh(queueWhenUnreachable: false)
            }
        }
    }
}

private struct MetricTile: View {
    var value: String
    var label: String
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(WatchTheme.accent)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SectionHeader: View {
    var title: String
    var icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct ServiceRow: View {
    var service: WatchServiceSummary

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(service.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var stateColor: Color {
        switch service.state {
        case .ready:
            return WatchTheme.success
        case .warning:
            return WatchTheme.warning
        case .notConfigured:
            return WatchTheme.muted
        }
    }
}

private struct DownloadRow: View {
    var item: WatchDownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text("\(Int(item.progressFraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: item.progressFraction)
                .tint(WatchTheme.accent)

            HStack {
                Text(item.status)
                Spacer()
                Text(item.timeLeft)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct UpcomingRow: View {
    var item: WatchUpcomingItem

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                Text(item.relativeDateText)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
            }
            .frame(width: 48)
            .frame(minHeight: 44)
            .background(WatchTheme.accent.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(item.kind) - \(item.detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyStateRow: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(WatchTheme.muted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum WatchTheme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let accent = Color(red: 0.0, green: 0.82, blue: 0.95)
    static let success = Color(red: 0.10, green: 0.72, blue: 0.46)
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.12)
    static let muted = Color.gray.opacity(0.7)
}

#Preview {
    WatchDashboardView()
}
