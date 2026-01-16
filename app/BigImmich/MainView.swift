import ImmichAPI
import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .albums

    @State private var albumID: AlbumID? = nil
    @State private var albumName: AlbumName? = nil
    @State private var assetID: AssetID? = nil

    @State private var isShowingSlideshow = false
    @State private var albumDetailsInitialyFocusedButton: ButtonFocus =
        .slideshow

    var body: some View {
        ZStack {
            if isShowingSlideshow, let curentAlbumID = albumID,
                let currentAlbumName = albumName
            {
                SlideshowView(
                    initialAlbumID: curentAlbumID,
                    initialAlbumName: currentAlbumName,
                    initialAssetID: assetID,
                    onExit: { exitAlbumID, exitAlbumName, exitAssetID in
                        selectedTab = .albumAssets

                        isShowingSlideshow = false
                        albumID = exitAlbumID
                        albumName = exitAlbumName
                        assetID = exitAssetID
                    },
                )
                .zIndex(50)
            } else {
                VStack {
                    Picker("Menu", selection: $selectedTab) {
                        Text("Albums").tag(Tab.albums)
                        if selectedTab == .albumAssets,
                            let albumName = albumName
                        {
                            Text(albumName.string).tag(Tab.albumAssets)
                        }
                        if selectedTab == .albumDetails,
                            let albumName = albumName
                        {
                            Text(albumName.string).tag(Tab.albumDetails)
                        }
                        Text("Settings").tag(Tab.settings)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 1200)
                    .padding(.top, 40)
                    .onChange(of: selectedTab) {
                        if selectedTab == .settings {
                            albumID = nil
                            albumName = nil
                            assetID = nil
                        }
                    }
                    .onExitCommand(perform: {
                        if selectedTab == .albumAssets {
                            selectedTab = .albumDetails
                        } else if selectedTab == .albumDetails {
                            selectedTab = .albums
                        } else {
                            albumID = nil
                            albumName = nil
                            assetID = nil
                        }
                    })

                    Spacer()

                    switch selectedTab {
                    case .albums:
                        AlbumsView(
                            initialAlbumID: albumID,
                            onSelectAlbum: {
                                selectedAlbumID,
                                selectedAlbumName in
                                albumID = selectedAlbumID
                                albumName = selectedAlbumName
                                assetID = nil
                                albumDetailsInitialyFocusedButton = .slideshow

                                selectedTab = .albumDetails
                            },
                        )
                    case .albumDetails:
                        if let currentAlbumID = albumID {
                            AlbumDetailsView(
                                albumID: currentAlbumID,
                                initialyFocusedButton:
                                    albumDetailsInitialyFocusedButton,
                                startSlideshow: {
                                    assetID = nil

                                    isShowingSlideshow = true
                                },
                                viewAssets: {
                                    assetID = nil

                                    selectedTab = .albumAssets
                                },
                                onExit: {
                                    selectedTab = .albums
                                },
                            )
                        }
                    case .albumAssets:
                        if let currentAlbumID = albumID {
                            AlbumAssetsView(
                                albumID: currentAlbumID,
                                initialAssetID: assetID,
                                startSlideshow: { exitAssetID in
                                    assetID = exitAssetID

                                    isShowingSlideshow = true
                                },
                                onExit: {
                                    selectedTab = .albumDetails
                                    albumDetailsInitialyFocusedButton =
                                        .viewAssets
                                },
                            )
                        }
                    case .settings:
                        SettingsView()
                            .onExitCommand(perform: {
                                albumID = nil
                                albumName = nil
                                assetID = nil

                                selectedTab = .albums
                            })
                    }

                    Spacer()
                }
            }
        }.onOpenURL { url in
            handleTopShelfURL(url)
        }
    }

    private func getQueryParamValue(queryItems: [URLQueryItem], key: String)
        -> String?
    {
        return queryItems.first(where: {
            $0.name == key
        })?.value
    }

    func handleTopShelfURL(_ url: URL) {
        guard url.scheme == "bigimmich" else { return }
        guard let host = url.host, host == "album" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let page = pathComponents.first, page == "details" else { return }

        let selectedAlbumID = getQueryParamValue(
            queryItems: queryItems,
            key: "albumID"
        )
        let selectedAlbumName = getQueryParamValue(
            queryItems: queryItems,
            key: "albumName"
        )
        guard let selectedAlbumID, let selectedAlbumName else { return }

        albumID = AlbumID(rawValue: selectedAlbumID)
        albumName = AlbumName(rawValue: selectedAlbumName)
        assetID = nil
        albumDetailsInitialyFocusedButton = .slideshow

        selectedTab = .albumDetails
    }
}

enum Tab: Hashable {
    case albums
    case albumAssets
    case albumDetails
    case settings
}
