import SwiftUI

struct EditMovieView: View {
    let movie: Movie
    @Environment(\.dismiss) var dismiss

    @State private var monitored: Bool
    @State private var selectedQualityProfileId: Int
    @State private var selectedMinimumAvailability: RadarrMinimumAvailability
    @State private var selectedTagIds: Set<Int>
    @State private var qualityProfiles: [RadarrQualityProfile] = []
    @State private var tags: [MediaTag] = []
    @State private var isLoadingOptions = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(movie: Movie) {
        self.movie = movie
        _monitored = State(initialValue: movie.monitored)
        _selectedQualityProfileId = State(initialValue: movie.qualityProfileId ?? 1)
        _selectedMinimumAvailability = State(initialValue: RadarrMinimumAvailability(rawValue: movie.minimumAvailability ?? "") ?? .released)
        _selectedTagIds = State(initialValue: Set(movie.tags ?? []))
    }

    private var selectedTagSummary: String {
        tagSummary(selectedTagIds: selectedTagIds, tags: tags)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Movie info header
                        VStack(spacing: AppSpacing.sm) {
                            Text(movie.title)
                                .font(AppTypography.title3())
                                .foregroundColor(ColorPalette.textPrimaryDark)
                                .multilineTextAlignment(.center)

                            Text(String(movie.year))
                                .font(AppTypography.subheadline())
                                .foregroundColor(ColorPalette.secondary)
                        }
                        .padding(.top, AppSpacing.lg)

                        // Quality profile section
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("QUALITY".uppercased())
                                .font(AppTypography.caption1(.semibold))
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Text("Quality Profile")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)

                                Spacer()

                                if isLoadingOptions {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(ColorPalette.secondary)
                                } else {
                                    Picker("Quality Profile", selection: $selectedQualityProfileId) {
                                        ForEach(qualityProfiles) { profile in
                                            Text(profile.name).tag(profile.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(ColorPalette.secondary)
                                }
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            Text("The quality profile determines which releases Radarr will download")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Text("Minimum Availability")
                                    .font(AppTypography.body())
                                    .foregroundColor(ColorPalette.textPrimaryDark)

                                Spacer()

                                Picker("Minimum Availability", selection: $selectedMinimumAvailability) {
                                    ForEach(RadarrMinimumAvailability.allCases) { availability in
                                        Text(availability.displayName).tag(availability)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(ColorPalette.secondary)
                                .disabled(isLoadingOptions)
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            if !tags.isEmpty {
                                TagSelectionMenuRow(
                                    title: "Tags",
                                    selectedLabel: selectedTagSummary,
                                    tags: tags,
                                    selectedTagIds: $selectedTagIds
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md)
                                        .stroke(ColorPalette.divider, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // Monitoring section
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("MONITORING".uppercased())
                                .font(AppTypography.caption1(.semibold))
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)

                            HStack {
                                Label {
                                    Text("Monitored")
                                        .font(AppTypography.body())
                                        .foregroundColor(ColorPalette.textPrimaryDark)
                                } icon: {
                                    Image(systemName: monitored ? "eye.fill" : "eye.slash.fill")
                                        .foregroundColor(monitored ? ColorPalette.primary : ColorPalette.textMutedDark)
                                        .frame(width: 28)
                                }

                                Spacer()

                                Toggle("", isOn: $monitored)
                                    .tint(ColorPalette.primary)
                                    .labelsHidden()
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(ColorPalette.cardBackgroundDark)
                            .cornerRadius(AppRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(ColorPalette.divider, lineWidth: 1)
                            )

                            Text("When monitored, Radarr will search for and download this movie automatically")
                                .font(AppTypography.caption2())
                                .foregroundColor(ColorPalette.textMutedDark)
                                .padding(.horizontal, AppSpacing.md)
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // Error message
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(ColorPalette.error)
                                Text(error)
                                    .font(AppTypography.subheadline())
                                    .foregroundColor(ColorPalette.error)
                            }
                            .padding(AppSpacing.md)
                            .frame(maxWidth: .infinity)
                            .background(ColorPalette.error.opacity(0.1))
                            .cornerRadius(AppRadius.md)
                            .padding(.horizontal, AppSpacing.md)
                        }

                        Spacer(minLength: AppSpacing.xl)
                    }
                }
            }
            .navigationTitle("Edit Movie")
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(ColorPalette.textSecondaryDark)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(ColorPalette.secondary)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.5 : 1)
                }
            }
            .onAppear {
                loadOptions()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadOptions() {
        Task {
            do {
                async let profilesTask = RadarrService.shared.fetchQualityProfiles()
                async let tagsTask: [MediaTag] = (try? await RadarrService.shared.fetchTags()) ?? []
                let (profiles, fetchedTags) = try await (profilesTask, tagsTask)
                await MainActor.run {
                    qualityProfiles = profiles
                    tags = fetchedTags
                    selectedTagIds = selectedTagIds.intersection(Set(fetchedTags.map(\.id)))
                    isLoadingOptions = false
                }
            } catch {
                await MainActor.run {
                    isLoadingOptions = false
                }
            }
        }
    }

    private func saveChanges() {
        isSaving = true
        errorMessage = nil

        let updatedMovie = Movie(
            id: movie.id,
            title: movie.title,
            year: movie.year,
            overview: movie.overview,
            runtime: movie.runtime,
            monitored: monitored,
            status: movie.status,
            images: movie.images,
            tmdbId: movie.tmdbId,
            qualityProfileId: selectedQualityProfileId,
            added: movie.added,
            digitalRelease: movie.digitalRelease,
            physicalRelease: movie.physicalRelease,
            inCinemas: movie.inCinemas,
            minimumAvailability: selectedMinimumAvailability.rawValue,
            rootFolderPath: movie.rootFolderPath,
            path: movie.path,
            tags: selectedTagIds.sorted()
        )

        Task {
            do {
                try await RadarrService.shared.updateMovie(movie: updatedMovie)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
