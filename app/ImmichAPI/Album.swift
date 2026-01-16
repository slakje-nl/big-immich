import Foundation

public struct Album: Codable, Identifiable, Hashable {
    public let id: AlbumID
    public let albumName: AlbumName
    public let albumThumbnailAssetId: AssetID
    public let createdAt: String
    public let updatedAt: String
    public let startDate: String
    public let lastModifiedAssetTimestamp: String
    public let assets: [AlbumAsset]

    static public func == (lhs: Album, rhs: Album) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct AlbumAsset: Codable, Identifiable {
    public let id: AssetID
    public let type: String
    public let originalPath: String
    public let duration: String
    public let exifInfo: ExifInfo?
}

public struct ExifInfo: Codable {
    public let dateTimeOriginal: String?
    public let city: String?
    public let state: String?
    public let country: String?
}
