//
//  ImmichClient.swift
//  BigImmich
//
//  Created by Maciej Płoński on 06/01/2026.
//

public enum AlbumsOrder: String, CaseIterable, Identifiable {
    case fromOldest
    case fromNewest

    public var id: String { rawValue }
}

public protocol ImmichClientProtocol {
    func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary]
    func getAlbum(albumID: AlbumID) async throws -> Album
}

public class ImmichClient: ImmichClientProtocol {
    public static let shared = ImmichClient()

    private init() {}

    private func joinAlbums(order: AlbumsOrder, albumLists: [[AlbumSummary]])
        -> [AlbumSummary]
    {
        var uniqueAlbums = [AlbumID: AlbumSummary]()
        for albumList in albumLists {
            for album in albumList {
                if uniqueAlbums[album.id] == nil {
                    uniqueAlbums[album.id] = album
                }
            }
        }

        switch order {
        case .fromOldest:
            return uniqueAlbums.values.sorted { $0.startDate < $1.startDate }
        case .fromNewest:
            return uniqueAlbums.values.sorted { $0.startDate > $1.startDate }
        }
    }

    public func findAlbums(order: AlbumsOrder) async throws -> [AlbumSummary] {
        let ownAlbums: [AlbumSummary] = try await ImmichAPI.shared.loadObject(
            path: "/api/albums",
            queryParams: [:],
        )
        let sharedAlbums: [AlbumSummary] = try await ImmichAPI.shared
            .loadObject(
                path: "/api/albums",
                queryParams: ["shared": "true"],
            )
        return joinAlbums(order: order, albumLists: [ownAlbums, sharedAlbums])
    }

    public func getAlbum(albumID: AlbumID) async throws -> Album {
        return try await ImmichAPI.shared.loadObject(
            path: "/api/albums/\(albumID.string)",
            queryParams: [:],
        )
    }
}
