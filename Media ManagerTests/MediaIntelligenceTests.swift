import Foundation
import Testing
@testable import Media_Manager

struct MediaIntelligenceTests {
    @Test
    func spokenChoicesDistinguishSameTitleAndYearWithoutReadingEveryCatalogID() {
        struct Result { let id: Int; let title: String; let year: Int }
        let results = [Result(id: 1, title: "Example", year: 2020), Result(id: 2, title: "Example", year: 2020), Result(id: 3, title: "Example", year: 1990), Result(id: 4, title: "Unknown Year", year: 0)]
        #expect(MediaEntityResolution.choiceLabels(results, title: \.title, year: \.year, id: \.id) == ["Example (2020) [1]", "Example (2020) [2]", "Example (1990)", "Unknown Year"])
    }

    @Test
    func catalogResultsDeduplicateAndRejectInvalidIdentities() {
        struct Result { let id: Int }
        let results = [Result(id: 0), Result(id: 42), Result(id: 42), Result(id: -1), Result(id: 8)]
        #expect(MediaEntityResolution.exactCatalogMatches(results, term: "Example", prefix: "tmdb", id: \.id).map(\.id) == [42, 8])
    }

    @Test
    func duplicateDetectionDoesNotHideRootFolderOrProfileErrors() {
        func error(_ property: String?, _ message: String) -> RadarrErrorResponse {
            RadarrErrorResponse(propertyName: property, errorMessage: message, attemptedValue: nil, severity: nil)
        }
        #expect(error("TmdbId", "This movie has already been added").isDuplicateCatalogID("TmdbId"))
        #expect(error("TvdbId", "This series has already been added").isDuplicateCatalogID("TvdbId"))
        #expect(!error("RootFolderPath", "Root folder already exists").isDuplicateCatalogID("TmdbId"))
        #expect(!error("QualityProfileId", "Profile does not exist").isDuplicateCatalogID("TvdbId"))
        #expect(!error(nil, "File already exists").isDuplicateCatalogID("TmdbId"))
        #expect(!error("TmdbId", "Movie does not exist").isDuplicateCatalogID("TmdbId"))
    }

    @Test
    func exactCatalogLookupNeverAddsAnUnrelatedResult() {
        struct Result { let id: Int }
        let items = [Result(id: 12), Result(id: 42)]
        #expect(MediaEntityResolution.exactCatalogMatches(items, term: "tmdb:42", prefix: "tmdb", id: \.id).map(\.id) == [42])
        #expect(MediaEntityResolution.exactCatalogMatches(items, term: "tmdb:999", prefix: "tmdb", id: \.id).isEmpty)
        #expect(MediaEntityResolution.exactCatalogMatches(items, term: "tmdb:bad", prefix: "tmdb", id: \.id).isEmpty)
        #expect(MediaEntityResolution.exactCatalogMatches(items, term: "Example", prefix: "tmdb", id: \.id).count == 2)
    }

    @Test @MainActor
    func resolutionPreservesIdentityOrderAndSkipsInvalidIDs() async throws {
        var requested: [Int] = []
        let result = try await MediaEntityResolution.resolve([8, -1, 0, 42, 8, 7]) { id in
            requested.append(id)
            return id == 7 ? nil : "catalog:\(id)"
        }
        #expect(requested == [8, 42, 7])
        #expect(result == ["catalog:8", "catalog:42"])
    }

    @Test @MainActor
    func resolutionDoesNotTurnServerFailuresIntoMissingTitles() async {
        do {
            let _: [Int] = try await MediaEntityResolution.resolve([1]) { _ in
                throw URLError(.notConnectedToInternet)
            }
            Issue.record("Expected lookup failure")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test
    func libraryEntityUsesCatalogIDRatherThanServerID() {
        let movie = Movie(id: 42, title: "Example", year: 2026, overview: nil, runtime: 90, monitored: true, status: "released", images: [], tmdbId: 800)
        #expect(MovieSearchResultEntity(libraryMovie: movie)?.id == 800)
        let missingID = Movie(id: 42, title: "Example", year: 2026, overview: nil, runtime: 90, monitored: true, status: "released", images: [])
        #expect(MovieSearchResultEntity(libraryMovie: missingID) == nil)
    }

    @Test
    func assistantContextIsBoundedAndExcludesServerPaths() {
        let movies = (1...100).map { id in
            Movie(id: id, title: "Title \(id)", year: 2026, overview: String(repeating: "Overview ", count: 100), runtime: 90, monitored: true, status: "released", images: [], tmdbId: id, rootFolderPath: "/private/library", path: "/private/movie")
        }
        let context = LibraryAssistantContext.make(movies: movies, shows: [], query: "")
        #expect(context.contains("100 movies"))
        #expect(context.contains("Partial title sample"))
        #expect(!context.contains("/private"))
        #expect(context.count < 6500)
    }

    @Test
    func searchHandlesWhitespaceCaseAndOverview() {
        #expect(LibraryAssistantContext.matches(" SPACE ", title: "Example", overview: "A space adventure"))
        #expect(LibraryAssistantContext.matches("  ", title: "Example", overview: nil))
        #expect(!LibraryAssistantContext.matches("missing", title: "Example", overview: nil))
    }

}
