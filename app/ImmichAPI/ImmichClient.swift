//
//  ImmichClient.swift
//  BigImmich
//
//  Created by Maciej Płoński on 06/01/2026.
//

public enum AlbumsOrder: String, CaseIterable, Identifiable {
    case fromOldest
    case fromNewest

    public var id: String {
        rawValue
    }
}

public protocol ImmichClientProtocol {
    func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary]
    func getAlbum(albumID: AlbumID) async throws -> Album
    func getAlbumAssets(albumID: AlbumID) async throws -> [AlbumAsset]
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
        let ownAlbums: [AlbumSummary] = try await ImmichAPI.shared.loadArray(
            path: "/api/albums",
            queryParams: [:]
        )
        let sharedAlbums: [AlbumSummary] = try await ImmichAPI.shared
            .loadArray(
                path: "/api/albums",
                queryParams: ["shared": "true"]
            )
        return joinAlbums(order: order, albumLists: [ownAlbums, sharedAlbums])
    }

    public func getAlbum(albumID: AlbumID) async throws -> Album {
        try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
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
