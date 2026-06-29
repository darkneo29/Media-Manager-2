import SwiftUI

struct WatchDashboardView: View {
    @StateObject private var store = WatchDashboardStore()

    private var snapshot: WatchDashboardSnapshot {
        store.snapshot
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    librarySummary
                    mediaActionsSection
                    servicesSection
                    downloadsSection
                    upcomingSection
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .background(WatchTheme.background)
            .navigationTitle("Dragon")
        }
        .task {
            store.activate()
            store.requestRefresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(WatchTheme.accent.opacity(0.18))
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WatchTheme.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Media Manager")
                    .font(.headline)
                    .lineLimit(1)
                Text(store.connectionStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                store.requestRefresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("Refresh")
        }
    }

    private var librarySummary: some View {
        HStack(spacing: 6) {
            MetricTile(value: "\(snapshot.library.movieCount)", label: "Movies", icon: "film.fill")
            MetricTile(value: "\(snapshot.library.showCount)", label: "Shows", icon: "tv.fill")
        }
    }

    private var mediaActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Add", icon: "mic.fill")

            Picker("Type", selection: $store.searchKind) {
                ForEach(WatchMediaKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()

            HStack(spacing: 6) {
                Button {
                    requestVoiceSearch()
                } label: {
                    Label("Speak", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)

                Button {
                    store.searchMedia(kind: store.searchKind, query: store.searchQuery)
                } label: {
                    if store.isSearching {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearching)
                .accessibilityLabel("Search")
            }

            TextField("Say or type a title", text: $store.searchQuery)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    store.searchMedia(kind: store.searchKind, query: store.searchQuery)
                }

            if !store.mediaActionStatus.isEmpty {
                Text(store.mediaActionStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(store.searchResults) { result in
                SearchResultRow(
                    result: result,
                    isAdding: store.addingResultId == result.id
                ) {
                    store.addMedia(result)
                }
            }
        }
        .padding(10)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func requestVoiceSearch() {
        WatchVoiceInput.requestTitle { phrase in
            guard let phrase else { return }
            store.searchQuery = phrase
            store.searchMedia(kind: store.searchKind, query: phrase)
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Services", icon: "server.rack")

            if snapshot.services.isEmpty {
                EmptyStateRow(
                    icon: "iphone",
                    title: "Open the iPhone app",
                    subtitle: "Watch data syncs from your configured phone app."
                )
            } else {
                ForEach(snapshot.services) { service in
                    ServiceRow(service: service)
                }
            }
        }
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Downloads", icon: "arrow.down.circle.fill")

            if !snapshot.downloads.isConfigured {
                EmptyStateRow(
                    icon: "gearshape",
                    title: "SabNZB not configured",
                    subtitle: "Set it up on iPhone to control downloads."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.downloads.statusText)
                                .font(.headline)
                                .lineLimit(1)
                            Text(snapshot.downloads.speedBytesPerSecond.watchFormattedBytesPerSecond)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            store.toggleDownloads()
                        } label: {
                            Image(systemName: snapshot.downloads.isPaused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(snapshot.downloads.isPaused ? WatchTheme.success : WatchTheme.warning)
                        .accessibilityLabel(snapshot.downloads.isPaused ? "Resume downloads" : "Pause downloads")
                    }

                    ForEach(snapshot.downloads.items) { item in
                        DownloadRow(item: item)
                    }
                }
                .padding(10)
                .background(WatchTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Upcoming", icon: "calendar")

            if snapshot.upcoming.isEmpty {
                EmptyStateRow(
                    icon: "calendar.badge.clock",
                    title: "No upcoming releases",
                    subtitle: snapshot.hasAnyConfiguredService ? "Refresh after your library loads on iPhone." : "Configure Radarr or Sonarr on iPhone."
                )
            } else {
                ForEach(snapshot.upcoming) { item in
                    UpcomingRow(item: item)
                }
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

private struct SearchResultRow: View {
    var result: WatchMediaSearchResult
    var isAdding: Bool
    var add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: result.kind == .movie ? "film.fill" : "tv.fill")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.accent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(result.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let overview = result.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                add()
            } label: {
                if isAdding {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Label("Add", systemImage: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.success)
            .disabled(isAdding)
        }
        .padding(8)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DownloadRow: View {
    var item: WatchDownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(item.progress))%")
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
