//
//  ImmichClient.swift
//  BigImmich
//
//  Created by Maciej Płoński on 06/01/2026.
//

import Foundation

public enum AlbumsOrder: String, CaseIterable, Identifiable {
    case fromOldest
    case fromNewest

    public var id: String {
        rawValue
    }
}

/// Requested rendition of an asset's thumbnail, mapped to the Immich `size` query param.
public enum ThumbnailSize {
    /// Small grid thumbnail (the endpoint default, no `size` param).
    case thumbnail
    case preview
    case fullsize

    var queryParams: [String: String] {
        switch self {
        case .thumbnail: [:]
        case .preview: ["size": "preview"]
        case .fullsize: ["size": "fullsize"]
        }
    }
}

public protocol ImmichClientProtocol {
    func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary]
    func getAlbum(albumID: AlbumID) async throws -> Album
    func getAlbumAssets(albumID: AlbumID) async throws -> [AlbumAsset]
    func getServerVersion() async throws -> ServerVersion
    func getAsset(assetID: AssetID) async throws -> AlbumAsset
    func loadThumbnail(assetID: AssetID, size: ThumbnailSize, retries: Int) async throws -> Data
    func thumbnailURL(assetID: AssetID, size: ThumbnailSize) async throws -> URL
    func videoPlaybackURL(assetID: AssetID) async throws -> URL
}

func joinAlbums(order: AlbumsOrder, albumLists: [[AlbumSummary]]) -> [AlbumSummary] {
    var uniqueAlbums = [AlbumID: AlbumSummary]()
    for albumList in albumLists {
        for album in albumList where uniqueAlbums[album.id] == nil {
            uniqueAlbums[album.id] = album
        }
    }

    let nonEmptyAlbums = uniqueAlbums.values.filter { ($0.assetCount ?? 1) > 0 }

    switch order {
    case .fromOldest:
        return nonEmptyAlbums.sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
    case .fromNewest:
        return nonEmptyAlbums.sorted { ($0.startDate ?? "") > ($1.startDate ?? "") }
    }
}

public class ImmichClient: ImmichClientProtocol {
    public static let shared = ImmichClient()

    private init() {}

    public func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary] {
        async let ownAlbums: [AlbumSummary] = ImmichAPI.shared.loadArray(
            path: "/api/albums",
            queryParams: [:]
        )
        async let sharedAlbums: [AlbumSummary] = ImmichAPI.shared.loadArray(
            path: "/api/albums",
            queryParams: ["shared": "true"]
        )
        return try await joinAlbums(
            order: order,
            albumLists: [ownAlbums, sharedAlbums]
        )
    }

    public func getAlbum(albumID: AlbumID) async throws -> Album {
        try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
            queryParams: [:]
        )
    }

    public func getAsset(assetID: AssetID) async throws -> AlbumAsset {
        try await ImmichAPI.shared.loadObject(
            path: "/api/assets/\(assetID.string)",
            queryParams: [:]
        )
    }

    public func loadThumbnail(
        assetID: AssetID,
        size: ThumbnailSize,
        retries: Int
    ) async throws -> Data {
        try await ImmichAPI.shared.loadMediaWithRetries(
            path: "/api/assets/\(assetID.string)/thumbnail",
            queryParams: size.queryParams,
            retries: retries
        )
    }

    public func thumbnailURL(
        assetID: AssetID,
        size: ThumbnailSize
    ) async throws -> URL {
        try await ImmichAPI.shared.getUrlWithQueryAuth(
            path: "/api/assets/\(assetID.string)/thumbnail",
            queryParams: size.queryParams
        )
    }

    public func videoPlaybackURL(assetID: AssetID) async throws -> URL {
        try await ImmichAPI.shared.getUrlWithQueryAuth(
            path: "/api/assets/\(assetID.string)/video/playback",
            queryParams: nil
        )
    }

    public func getServerVersion() async throws -> ServerVersion {
        try await ImmichAPI.shared.loadObject(
            path: "/api/server/version",
            queryParams: [:]
        )
    }

    public func getAlbumAssets(albumID: AlbumID) async throws -> [AlbumAsset] {
        var assets: [AlbumAsset] = []
        var page = 1

        while true {
            let response: SearchResponse = try await ImmichAPI.shared.postObject(
                path: "/api/search/metadata",
                jsonPayload: ["albumIds": [albumID.string], "page": page, "size": 1000]
            )
            assets.append(contentsOf: response.assets.items)

            guard let next = response.assets.nextPage, let nextPage = Int(next) else {
                break
            }
            page = nextPage
        }

        return assets
    }
}
