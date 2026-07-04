import Combine
import Foundation
import ImmichAPI

enum Tab: Hashable {
    case albums
    case albumAssets
    case albumDetails
    case settings
}

final class AppRouter: ObservableObject {
    @Published var selectedTab: Tab = .albums
    @Published var albumID: AlbumID?
    @Published var albumName: AlbumName?
    @Published var assetID: AssetID?
    @Published var isShowingSlideshow = false
    @Published var albumDetailsInitialFocus: ButtonFocus = .slideshow

    func selectAlbum(_ id: AlbumID, _ name: AlbumName) {
        albumID = id
        albumName = name
        assetID = nil
        albumDetailsInitialFocus = .slideshow
        selectedTab = .albumDetails
    }

    func startSlideshow(assetID: AssetID?) {
        self.assetID = assetID
        isShowingSlideshow = true
    }

    func exitSlideshow(albumID: AlbumID, albumName: AlbumName, assetID: AssetID?) {
        selectedTab = .albumAssets
        isShowingSlideshow = false
        self.albumID = albumID
        self.albumName = albumName
        self.assetID = assetID
    }

    func viewAssets() {
        assetID = nil
        selectedTab = .albumAssets
    }

    func exitAlbumDetails() {
        selectedTab = .albums
    }

    func exitAlbumAssets() {
        selectedTab = .albumDetails
        albumDetailsInitialFocus = .viewAssets
    }

    func exitSettings() {
        clearSelection()
        selectedTab = .albums
    }

    func handleTabChange() {
        if selectedTab == .settings {
            clearSelection()
        }
    }

    func handleExitCommand() {
        if selectedTab == .albumAssets {
            selectedTab = .albumDetails
        } else if selectedTab == .albumDetails {
            selectedTab = .albums
        } else {
            clearSelection()
        }
    }

    func openTopShelfLink(_ url: URL) {
        guard let link = parseTopShelfAlbumLink(url) else { return }

        albumID = link.albumID
        albumName = link.albumName
        assetID = nil
        albumDetailsInitialFocus = .slideshow
        selectedTab = .albumDetails
    }

    private func clearSelection() {
        albumID = nil
        albumName = nil
        assetID = nil
    }
}
