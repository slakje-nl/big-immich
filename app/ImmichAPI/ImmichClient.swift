//
//  ImmichClient.swift
//  BigImmich
//
//  Created by Maciej Płoński on 06/01/2026.
//

public class ImmichClient {
    public static let shared = ImmichClient()

    private init() {}

    private func joinAlbums(_ albumLists: [Album]...) -> [Album] {
        let allAlbums = albumLists.flatMap { $0 }

        var uniqueAlbums = [AlbumID: Album]()
        for album in allAlbums {
            if uniqueAlbums[album.id] == nil {
                uniqueAlbums[album.id] = album
            }
        }

        return uniqueAlbums.values.sorted { $0.startDate > $1.startDate }
    }

    public func findAlbums() async throws -> [Album] {
        let ownAlbums: [Album] = try await ImmichAPI.shared.loadObject(
            path: "/api/albums",
            queryParams: [:],
        )
        let sharedAlbums: [Album] = try await ImmichAPI.shared.loadObject(
            path: "/api/albums",
            queryParams: ["shared": "true"],
        )
        return joinAlbums(ownAlbums, sharedAlbums)
    }
}
