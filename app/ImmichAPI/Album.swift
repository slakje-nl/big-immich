import Foundation

public struct AlbumSummary: Codable, Identifiable, Hashable {
    public let id: AlbumID
    public let albumName: AlbumName
    public let albumThumbnailAssetId: AssetID
    public let createdAt: String
    public let updatedAt: String
    public let startDate: String
    public let lastModifiedAssetTimestamp: String

    public init(
        id: AlbumID,
        albumName: AlbumName,
        albumThumbnailAssetId: AssetID,
        createdAt: String,
        updatedAt: String,
        startDate: String,
        lastModifiedAssetTimestamp: String
    ) {
        self.id = id
        self.albumName = albumName
        self.albumThumbnailAssetId = albumThumbnailAssetId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startDate = startDate
        self.lastModifiedAssetTimestamp = lastModifiedAssetTimestamp
    }

    static public func == (lhs: AlbumSummary, rhs: AlbumSummary) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct Album: Codable, Identifiable, Hashable {
    public let id: AlbumID
    public let albumName: AlbumName
    public let albumThumbnailAssetId: AssetID
    public let createdAt: String
    public let updatedAt: String
    public let startDate: String
    public let lastModifiedAssetTimestamp: String
    public let assets: [AlbumAsset]

    public init(
        id: AlbumID,
        albumName: AlbumName,
        albumThumbnailAssetId: AssetID,
        createdAt: String,
        updatedAt: String,
        startDate: String,
        lastModifiedAssetTimestamp: String,
        assets: [AlbumAsset],
    ) {
        self.id = id
        self.albumName = albumName
        self.albumThumbnailAssetId = albumThumbnailAssetId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startDate = startDate
        self.lastModifiedAssetTimestamp = lastModifiedAssetTimestamp
        self.assets = assets
    }

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

    public init(
        id: AssetID,
        type: String,
        originalPath: String,
        duration: String,
        exifInfo: ExifInfo? = nil
    ) {
        self.id = id
        self.type = type
        self.originalPath = originalPath
        self.duration = duration
        self.exifInfo = exifInfo
    }
}

public struct ExifInfo: Codable {
    public let dateTimeOriginal: String?
    public let city: String?
    public let state: String?
    public let country: String?
}
