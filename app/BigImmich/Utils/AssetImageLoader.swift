import ImmichAPI
import SwiftUI

/// Single decode/cache path for asset thumbnails shared by the grid thumbnails, the album
/// detail hero image and the slideshow (current + preloaded assets).
///
/// Fetches thumbnail bytes through an injected `ImmichClientProtocol`, decodes them into a
/// SwiftUI `Image` and — when a cache is configured — stores the result keyed by asset id.
final class AssetImageLoader {
    private let immichClient: ImmichClientProtocol
    private let cache: MemoryCache<AssetID, Image>?

    init(
        immichClient: ImmichClientProtocol = ImmichClient.shared,
        cacheCountLimit: Int? = nil
    ) {
        self.immichClient = immichClient
        cache = cacheCountLimit.map { MemoryCache(countLimit: $0, megaBytesLimit: nil) }
    }

    func clear() {
        cache?.clear()
    }

    /// Fetches, decodes and (when a cache is configured) stores the image for `assetID`.
    /// Returns a cached image immediately when present, so callers can use `load` both to
    /// display and to warm the cache. Throws `URLError(.cannotDecodeContentData)` on decode
    /// failure and rethrows any network error.
    @discardableResult
    func load(
        assetID: AssetID,
        size: ThumbnailSize,
        retries: Int
    ) async throws -> Image {
        if let cached = cache?.get(assetID) {
            return cached
        }

        let data = try await immichClient.loadThumbnail(
            assetID: assetID,
            size: size,
            retries: retries
        )
        guard let uiImage = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        let image = Image(uiImage: uiImage)
        cache?.set(assetID, value: image)
        return image
    }
}
