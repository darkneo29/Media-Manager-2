import SwiftUI

struct CachedAsyncImageLoadState {
    var image: UIImage?
    var isLoading = false
    private(set) var activeRequestID = UUID()

    @discardableResult
    mutating func beginRequest(for url: URL?) -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        image = nil
        isLoading = url != nil
        return requestID
    }

    mutating func completeRequest(_ fetchedImage: UIImage?, requestID: UUID) {
        guard activeRequestID == requestID else { return }
        image = fetchedImage
        isLoading = false
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    @State private var loadState = CachedAsyncImageLoadState()

    var body: some View {
        Group {
            if let image = loadState.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.cardBackgroundDark,
                                ColorPalette.surfaceDark
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        if loadState.isLoading {
                            ProgressView()
                                .tint(ColorPalette.primary)
                        } else {
                            Image(systemName: "film")
                                .font(.system(size: min(width, height) * 0.3))
                                .foregroundColor(ColorPalette.textMutedDark.opacity(0.5))
                        }
                    }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: url) {
            let requestID = loadState.beginRequest(for: url)
            guard let url = url else {
                return
            }

            let fetchedImage = await ImageCacheManager.shared.image(for: url)
            loadState.completeRequest(fetchedImage, requestID: requestID)
        }
    }
}
