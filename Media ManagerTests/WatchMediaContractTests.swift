import Foundation
import Testing
@testable import Media_Manager

struct WatchMediaContractTests {
    @Test func olderSearchResultsRemainDecodable() throws {
        let data = Data(#"{"kind":"movie","remoteId":42,"title":"Example","year":2026,"subtitle":"Movie"}"#.utf8)
        let result = try JSONDecoder().decode(WatchMediaSearchResult.self, from: data)
        #expect(result.isInLibrary == nil)
        #expect(result.id == "movie-42")
    }

    @Test func libraryStateSurvivesSearchReplyRoundTrip() throws {
        let result = WatchMediaSearchResult(kind: .movie, remoteId: 42, title: "Example", year: 2026, subtitle: "Movie", isInLibrary: true)
        let response = WatchMediaSearchResponse(requestId: UUID(), kind: .movie, query: "Example", results: [result])
        let decoded = try JSONDecoder().decode(WatchMediaSearchResponse.self, from: JSONEncoder().encode(response))
        #expect(decoded == response)
        #expect(decoded.results.first?.isInLibrary == true)
    }

    @Test func downloadProgressClampsOutOfRangeValues() {
        var item = WatchDownloadItem(id: "1", name: "Example", status: "Downloading", progress: -5, timeLeft: "", speedBytesPerSecond: 0)
        #expect(item.progressFraction == 0)
        item.progress = 150
        #expect(item.progressFraction == 1)
    }
}
