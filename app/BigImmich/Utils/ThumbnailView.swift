import ImmichAPI
import Sentry
import SwiftUI

struct ThumbnailView: View {
    let assetID: AssetID
    let isVideo: Bool
    let isHighlighted: Bool
    let onLoaded: () -> Void
    let onError: (Error) -> Void

    @State private var image: Image?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .frame(height: 150)
            } else {
                Color.gray
                    .frame(height: 150)
            }

            if isVideo {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(8)
            }
        }
        .task {
            await loadThumbnail()
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .focusable(true)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.white : Color.clear, lineWidth: 6)
        )
        .shadow(color: isHighlighted ? .white.opacity(0.8) : .clear, radius: 8)
        .scaleEffect(isHighlighted ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private func loadThumbnail() async {
        isLoading = true
        do {
            let data: Data = try await ImmichAPI.shared.loadMediaWithRetries(
                path: "/api/assets/\(assetID.string)/thumbnail",
                queryParams: [:],
                retries: 3
            )
            if let uiImage = UIImage(data: data) {
                image = Image(uiImage: uiImage)
            } else {
                throw URLError(.cannotDecodeContentData)
            }
        } catch {
            if !(error is CancellationError) {
                onError(error)
                logError(error)
            }
        }
        isLoading = false
        onLoaded()
    }
}
