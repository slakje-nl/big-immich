import ImmichAPI
import SwiftUI

struct ContentView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            if router.isShowingSlideshow, let albumID = router.albumID,
               let albumName = router.albumName
            {
                SlideshowView(
                    initialAlbumID: albumID,
                    initialAlbumName: albumName,
                    initialAssetID: router.assetID,
                    onExit: { exitAlbumID, exitAlbumName, exitAssetID in
                        router.exitSlideshow(
                            albumID: exitAlbumID,
                            albumName: exitAlbumName,
                            assetID: exitAssetID
                        )
                    }
                )
                .zIndex(50)
            } else {
                VStack {
                    Picker("Menu", selection: $router.selectedTab) {
                        Text("Albums").tag(Tab.albums)
                        if router.selectedTab == .albumAssets,
                           let albumName = router.albumName
                        {
                            Text(albumName.string).tag(Tab.albumAssets)
                        }
                        if router.selectedTab == .albumDetails,
                           let albumName = router.albumName
                        {
                            Text(albumName.string).tag(Tab.albumDetails)
                        }
                        Text("Settings").tag(Tab.settings)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 1200)
                    .padding(.top, 40)
                    .onChange(of: router.selectedTab) {
                        router.handleTabChange()
                    }
                    .onExitCommand(perform: router.handleExitCommand)

                    Spacer()

                    tabContent

                    Spacer()
                }
            }
        }.onOpenURL { url in
            router.openTopShelfLink(url)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.selectedTab {
        case .albums:
            AlbumsView(
                initialAlbumID: router.albumID,
                onSelectAlbum: { selectedAlbumID, selectedAlbumName in
                    router.selectAlbum(selectedAlbumID, selectedAlbumName)
                }
            )
        case .albumDetails:
            if let albumID = router.albumID {
                AlbumDetailsView(
                    albumID: albumID,
                    initialyFocusedButton: router.albumDetailsInitialFocus,
                    startSlideshow: {
                        router.startSlideshow(assetID: nil)
                    },
                    viewAssets: {
                        router.viewAssets()
                    },
                    onExit: {
                        router.exitAlbumDetails()
                    }
                )
            }
        case .albumAssets:
            if let albumID = router.albumID {
                AlbumAssetsView(
                    albumID: albumID,
                    initialAssetID: router.assetID,
                    startSlideshow: { exitAssetID in
                        router.startSlideshow(assetID: exitAssetID)
                    },
                    onExit: {
                        router.exitAlbumAssets()
                    }
                )
            }
        case .settings:
            SettingsView()
                .onExitCommand(perform: router.exitSettings)
        }
    }
}
