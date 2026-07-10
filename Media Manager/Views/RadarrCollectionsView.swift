import SwiftUI

struct RadarrCollectionsView: View {
    @State private var collections: [RadarrCollection] = []
    @State private var isLoading = true
    @State private var updatingId: Int?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && collections.isEmpty {
                ProgressView("Loading collections…")
            } else if collections.isEmpty {
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "rectangle.stack",
                    description: Text("Collections created by Radarr will appear here.")
                )
            } else {
                List {
                    ForEach(collections) { collection in
                        collectionRow(collection)
                            .listRowBackground(ColorPalette.cardBackgroundDark)
                    }
                }
                .collectionsScrollStyle()
                .refreshable { await load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.backgroundDark)
        .navigationTitle("Collections")
        .navBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Collection Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The request could not be completed.")
        }
    }

    private func collectionRow(_ collection: RadarrCollection) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(collection.displayTitle)
                        .font(AppTypography.headline())
                        .foregroundColor(ColorPalette.textPrimaryDark)
                    Text(collection.missingMovies == 1 ? "1 missing movie" : "\(collection.missingMovies) missing movies")
                        .font(AppTypography.caption1())
                        .foregroundColor(collection.missingMovies > 0 ? ColorPalette.warning : ColorPalette.success)
                }
                Spacer()
                if updatingId == collection.id { ProgressView() }
            }

            Toggle("Monitor Collection", isOn: Binding(
                get: { collection.monitored },
                set: { update(collection, monitored: $0) }
            ))
            .tint(ColorPalette.primary)
            .disabled(updatingId != nil)

            Toggle("Search New Movies on Add", isOn: Binding(
                get: { collection.searchOnAdd },
                set: { update(collection, searchOnAdd: $0) }
            ))
            .tint(ColorPalette.primary)
            .disabled(updatingId != nil)

            if collection.missingMovies > 0 {
                Button {
                    update(collection, monitorMovies: true)
                } label: {
                    Label("Monitor Missing Collection Movies", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ColorPalette.secondary)
                .disabled(updatingId != nil)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func load() async {
        isLoading = true
        do {
            let values = try await RadarrService.shared.fetchCollections()
            await MainActor.run {
                collections = values.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func update(
        _ collection: RadarrCollection,
        monitored: Bool? = nil,
        monitorMovies: Bool? = nil,
        searchOnAdd: Bool? = nil
    ) {
        updatingId = collection.id
        Task {
            do {
                try await RadarrService.shared.updateCollection(
                    id: collection.id,
                    monitored: monitored,
                    monitorMovies: monitorMovies,
                    searchOnAdd: searchOnAdd
                )
                await load()
                await MainActor.run { updatingId = nil }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    updatingId = nil
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func collectionsScrollStyle() -> some View {
        #if os(tvOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }
}
