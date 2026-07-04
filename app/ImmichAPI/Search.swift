import Foundation

struct SearchResponse: Decodable {
    let assets: SearchAssets
}

struct SearchAssets: Decodable {
    let items: [AlbumAsset]
    let nextPage: String?
}
