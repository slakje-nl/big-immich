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
    /// The original file rendition (`size=original`); largest.
    case original

    var queryParams: [String: String] {
        switch self {
        case .thumbnail: [:]
        case .preview: ["size": "preview"]
        case .fullsize: ["size": "fullsize"]
        case .original: ["size": "original"]
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
    func hlsStream(assetID: AssetID) async throws -> HLSStream
    func endHLSSession(assetID: AssetID, sessionID: String) async
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

    /// Resolves an HLS streaming session for `assetID`: fetches the master playlist (which
    /// requires the server to have real-time transcoding enabled — otherwise this throws and the
    /// caller falls back to `videoPlaybackURL`), parses its variants, and returns everything the
    /// player needs, including the header auth that HLS sub-requests require.
    public func hlsStream(assetID: AssetID) async throws -> HLSStream {
        let path = "/api/assets/\(assetID.string)/video/stream/main.m3u8"
        let data = try await ImmichAPI.shared.loadMedia(path: path, queryParams: nil)
        let playlist = String(decoding: data, as: UTF8.self)
        let masterURL = try await ImmichAPI.shared.mediaURL(path: path, queryParams: nil)
        let headers = try await ImmichAPI.shared.mediaAuthHeaders()

        let variants = HLSPlaylistParser.parseVariants(playlist: playlist, masterURL: masterURL)
        guard let firstVariant = variants.first,
              let sessionID = HLSPlaylistParser.sessionID(fromVariantURI: firstVariant.playlistURL.path)
        else {
            throw ImmichAPIError.badResponse
        }

        return HLSStream(
            sessionID: sessionID,
            masterURL: masterURL,
            authHeaders: headers,
            variants: variants
        )
    }

    /// Releases the server-side transcoding session. Best-effort — failures are ignored since the
    /// server also times sessions out on its own.
    public func endHLSSession(assetID: AssetID, sessionID: String) async {
        let path = "/api/assets/\(assetID.string)/video/stream/\(sessionID)"
        try? await ImmichAPI.shared.sendRequest(httpMethod: "DELETE", path: path)
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
