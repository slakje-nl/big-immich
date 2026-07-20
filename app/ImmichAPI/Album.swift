import Foundation

public struct AlbumSummary: Codable, Identifiable, Hashable {
    public let id: AlbumID
    public let albumName: AlbumName
    public let albumThumbnailAssetId: AssetID?
    public let startDate: String?
    public let assetCount: Int?

    public init(
        id: AlbumID,
        albumName: AlbumName,
        albumThumbnailAssetId: AssetID?,
        startDate: String?,
        assetCount: Int?
    ) {
        self.id = id
        self.albumName = albumName
        self.albumThumbnailAssetId = albumThumbnailAssetId
        self.startDate = startDate
        self.assetCount = assetCount
    }

    public static func == (lhs: AlbumSummary, rhs: AlbumSummary) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct Album: Codable, Identifiable, Hashable {
    public let id: AlbumID
    public let albumName: AlbumName
    public let albumThumbnailAssetId: AssetID?
    public let assetCount: Int?
    /// ISO timestamp of the album's last asset change; used to invalidate cached
    /// per-album computations (e.g. the slideshow duration).
    public let lastModifiedAssetTimestamp: String?

    public init(
        id: AlbumID,
        albumName: AlbumName,
        albumThumbnailAssetId: AssetID?,
        assetCount: Int? = nil,
        lastModifiedAssetTimestamp: String? = nil
    ) {
        self.id = id
        self.albumName = albumName
        self.albumThumbnailAssetId = albumThumbnailAssetId
        self.assetCount = assetCount
        self.lastModifiedAssetTimestamp = lastModifiedAssetTimestamp
    }

    public static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum AssetType {
    case image
    case video
    case other
}

public struct AlbumAsset: Codable, Identifiable {
    public let id: AssetID
    public let type: String
    public let durationMilliseconds: Int?
    public let originalFileName: String?
    public let exifInfo: ExifInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case exifInfo
        case originalFileName
        case durationMilliseconds = "duration"
    }

    public init(
        id: AssetID,
        type: String,
        durationMilliseconds: Int?,
        originalFileName: String? = nil,
        exifInfo: ExifInfo? = nil
    ) {
        self.id = id
        self.type = type
        self.durationMilliseconds = durationMilliseconds
        self.originalFileName = originalFileName
        self.exifInfo = exifInfo
    }

    public var assetType: AssetType {
        switch type.uppercased() {
        case "IMAGE": .image
        case "VIDEO": .video
        default: .other
        }
    }
}

public struct ExifInfo: Codable {
    public let dateTimeOriginal: String?
    public let city: String?
    public let state: String?
    public let country: String?
    public let exifImageWidth: Int?
    public let exifImageHeight: Int?
    public let fileSizeInByte: Int?

    public init(
        dateTimeOriginal: String?,
        city: String?,
        state: String?,
        country: String?,
        exifImageWidth: Int? = nil,
        exifImageHeight: Int? = nil,
        fileSizeInByte: Int? = nil
    ) {
        self.dateTimeOriginal = dateTimeOriginal
        self.city = city
        self.state = state
        self.country = country
        self.exifImageWidth = exifImageWidth
        self.exifImageHeight = exifImageHeight
        self.fileSizeInByte = fileSizeInByte
    }
}
