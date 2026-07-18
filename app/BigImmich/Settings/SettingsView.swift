import Combine
import ImmichAPI
import KeychainHelper
import SwiftUI

struct SettingsView: View {
    // immich settings, saved to the Keychain
    @State private var immichURL: String = ""
    @State private var immichAuthMethod: ImmichAPIAuthMethod = .apiKey
    @State private var immichAuthAPIKey: String = ""
    @State private var immichAuthEmail: String = ""
    @State private var immichAuthPassword: String = ""

    // slideshow settings
    @AppStorage("slideshowInterval") private var slideshowInterval: Int = 5
    @AppStorage("slideshowDirection") private var slideshowDirection:
        SlideshowDirection = .oldestToNewest
    @AppStorage("slideshowLeftAction") private var slideshowLeftAction:
        SlideshowAction = .goToNext
    @AppStorage("slideshowRightAction") private var slideshowRightAction:
        SlideshowAction = .goToPrevious
    @AppStorage("slideshowOnceEndedAction") private var slideshowOnceEndedAction: SlideshowOnceEndedAction = .stopAndNotify
    @AppStorage("slideshowOnceEndedAnotherAlbum") private var slideshowOnceEndedAnotherAlbumSelection:
        SlideshowOnceEndedAnotherAlbumSelection = .random
    @AppStorage("slideshowShowProgressBar") private var slideshowShowProgressBar: SlideshowShowProgressBar = .always

    // performance
    @AppStorage("slideshowImageQuality") private var slideshowImageQuality: SlideshowImageQuality = .fullsize
    @AppStorage(ImageDiskCache.thumbnailsEnabledDefaultsKey) private var cacheThumbnails: Bool = true
    @AppStorage(ImageDiskCache.fullSizeEnabledDefaultsKey) private var cacheFullSizeImages: Bool = false
    @State private var imageCacheSize: String = "…"

    // error reporting
    @AppStorage("sentryEnabled") private var sentryEnabled: Bool = false
    @AppStorage("sentryDSN") private var sentryDSN: String = ""

    @State private var fakedPickerOption: Int = 0 // helper for pickers with a single option

    @State private var errorWhileSaving: Bool = false

    @State private var configurationError: String?
    @State private var configurationErrorColour: Color = .white
    @State private var connectionTested: Bool = false
    @State private var connectionWorking: Bool = true

    @ObservedObject private var appLog = AppLog.shared
    @State private var outdatedServer = false

    var immichClient: ImmichClientProtocol = ImmichClient.shared

    private let leftSideWidth: CGFloat = 280
    private let minimumImmichVersion = ServerVersion(major: 3, minor: 0, patch: 1)

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 30) {
                        if errorWhileSaving {
                            Text("Error saving settings!")
                                .foregroundColor(.red)
                                .bold()
                        }

                        HStack {
                            Text("Auth method")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("Auth method", selection: $immichAuthMethod) {
                                Text("api key (recommended)").tag(
                                    ImmichAPIAuthMethod.apiKey
                                )
                                Text("password").tag(
                                    ImmichAPIAuthMethod.emailAndPassword
                                )
                            }
                            .pickerStyle(.inline)
                            .frame(width: geo.size.width * 0.4)
                            .onChange(of: immichAuthMethod, saveSettings)
                        }

                        HStack {
                            Text("Immich URL")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            TextField("Enter Immich URL", text: $immichURL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                                .padding(8)
                                .cornerRadius(6)
                                .frame(width: geo.size.width * 0.4)
                                .onChange(of: immichURL, saveSettings)
                                .accessibilityIdentifier("immichURLField")
                        }

                        switch immichAuthMethod {
                        case .apiKey:
                            HStack {
                                Text("API Key")
                                    .frame(
                                        width: leftSideWidth,
                                        alignment: .leading
                                    )
                                    .bold()

                                SecureField(
                                    "Enter API Key",
                                    text: $immichAuthAPIKey
                                )
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(8)
                                .cornerRadius(6)
                                .frame(width: geo.size.width * 0.4)
                                .onChange(of: immichAuthAPIKey, saveSettings)
                                .accessibilityIdentifier("apiKeyField")
                            }

                            Text(
                                "Required api key permissions: album.read, asset.view, asset.download"
                            )
                            .foregroundColor(.white)
                            Text(
                                "Tip: use the Apple TV remote app on your iPhone to copy the api key"
                            )
                            .foregroundColor(.white)

                        case .emailAndPassword:
                            HStack {
                                Text("Email")
                                    .frame(
                                        width: leftSideWidth,
                                        alignment: .leading
                                    )
                                    .bold()

                                TextField("Enter email", text: $immichAuthEmail)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .keyboardType(.emailAddress)
                                    .padding(8)
                                    .cornerRadius(6)
                                    .frame(width: geo.size.width * 0.4)
                                    .onChange(of: immichAuthEmail, saveSettings)
                            }

                            HStack {
                                Text("Password")
                                    .frame(
                                        width: leftSideWidth,
                                        alignment: .leading
                                    )
                                    .bold()

                                SecureField(
                                    "Enter password",
                                    text: $immichAuthPassword
                                )
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(8)
                                .cornerRadius(6)
                                .frame(width: geo.size.width * 0.4)
                                .onChange(of: immichAuthPassword, saveSettings)
                            }
                        }

                        if let configurationError {
                            Text(configurationError).foregroundColor(
                                configurationErrorColour
                            )
                        } else if connectionTested {
                            if connectionWorking {
                                Text("Connection to Immich works!")
                                    .foregroundColor(.green)
                                if outdatedServer {
                                    Text(
                                        "This app is designed for Immich \(minimumImmichVersion.displayString) or newer. Updating Immich is recommended."
                                    )
                                    .foregroundColor(.yellow)
                                }
                            } else {
                                Text("Couldn't connect to Immich :(")
                                    .foregroundColor(.red)
                            }
                        }

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        Text("Found an issue or a missing feature?").bold()
                            .padding(.bottom, 10)

                        Text("Report it on our GitHub to improve this app!")
                        Text(
                            "Visit: https://github.com/slakje-nl/big-immich"
                        )

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        Text("Slideshow:")
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                            .bold()

                        HStack {
                            Text("Interval")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("Interval", selection: $slideshowInterval) {
                                ForEach(5 ... 60, id: \.self) { i in
                                    Text("\(i)s").tag(i)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Direction")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("Direction", selection: $slideshowDirection) {
                                Text("oldest → newest").tag(
                                    SlideshowDirection.oldestToNewest
                                )
                                Text("newest → oldest").tag(
                                    SlideshowDirection.newestToOldest
                                )
                                Text("randomized").tag(
                                    SlideshowDirection.randomized
                                )
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Once ended")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker(
                                "Direction",
                                selection: $slideshowOnceEndedAction
                            ) {
                                Text("stop and show a message").tag(
                                    SlideshowOnceEndedAction.stopAndNotify
                                )
                                Text("start again").tag(
                                    SlideshowOnceEndedAction.startAgain
                                )
                                Text(
                                    "load another album (choose the next one below)"
                                ).tag(
                                    SlideshowOnceEndedAction.loadAnotherAlbum
                                )
                            }
                            .pickerStyle(.menu)
                        }

                        if slideshowOnceEndedAction == .loadAnotherAlbum {
                            HStack {
                                Text("Next album")
                                    .frame(
                                        width: leftSideWidth,
                                        alignment: .leading
                                    )
                                    .bold()

                                Picker(
                                    "Another album",
                                    selection:
                                    $slideshowOnceEndedAnotherAlbumSelection
                                ) {
                                    Text("older").tag(
                                        SlideshowOnceEndedAnotherAlbumSelection
                                            .older
                                    )
                                    Text("newer").tag(
                                        SlideshowOnceEndedAnotherAlbumSelection
                                            .newer
                                    )
                                    Text("random").tag(
                                        SlideshowOnceEndedAnotherAlbumSelection
                                            .random
                                    )
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        HStack {
                            Text("Progress bar")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker(
                                "Progress bar",
                                selection: $slideshowShowProgressBar
                            ) {
                                Text("show").tag(
                                    SlideshowShowProgressBar.always
                                )
                                Text("don't show").tag(
                                    SlideshowShowProgressBar.never
                                )
                            }
                            .pickerStyle(.inline)
                            .frame(width: geo.size.width * 0.3)
                        }

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        Text("Slideshow controls:")
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                            .bold()

                        HStack {
                            Text("play")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("play", selection: $fakedPickerOption) {
                                Text("play / pause").tag(0)
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("up (video)")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("up", selection: $fakedPickerOption) {
                                Text("seek forward 15 seconds (if able)").tag(0)
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("down (video)")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("down", selection: $fakedPickerOption) {
                                Text("seek backwards 15 seconds (if able)").tag(
                                    0
                                )
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("left")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("left", selection: $slideshowLeftAction) {
                                Text("go to the next asset").tag(
                                    SlideshowAction.goToNext
                                )
                                Text("go to the previous asset").tag(
                                    SlideshowAction.goToPrevious
                                )
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("right")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("left", selection: $slideshowRightAction) {
                                Text("go to the next asset").tag(
                                    SlideshowAction.goToNext
                                )
                                Text("go to the previous asset").tag(
                                    SlideshowAction.goToPrevious
                                )
                            }
                            .pickerStyle(.menu)
                        }

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        Text("Performance:")
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                            .bold()

                        HStack {
                            Text("Slideshow quality")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker(
                                "Slideshow quality",
                                selection: $slideshowImageQuality
                            ) {
                                Text("thumbnail").tag(SlideshowImageQuality.thumbnail)
                                Text("preview").tag(SlideshowImageQuality.preview)
                                Text("full-size (recommended)").tag(SlideshowImageQuality.fullsize)
                                Text("original").tag(SlideshowImageQuality.original)
                            }
                            .pickerStyle(.menu)
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                        }

                        HStack {
                            Text("Cache thumbnails")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker(
                                "Cache thumbnails",
                                selection: $cacheThumbnails
                            ) {
                                Text("true").tag(true)
                                Text("false").tag(false)
                            }
                            .pickerStyle(.inline)
                            .frame(width: geo.size.width * 0.3)
                        }

                        HStack {
                            Text("Cache slideshow")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker(
                                "Cache slideshow",
                                selection: $cacheFullSizeImages
                            ) {
                                Text("true").tag(true)
                                Text("false").tag(false)
                            }
                            .pickerStyle(.inline)
                            .frame(width: geo.size.width * 0.3)
                        }

                        Text("Caches full-size photos, uses more space.")
                            .foregroundColor(.white)
                            .frame(
                                width: leftSideWidth + geo.size.width * 0.4,
                                alignment: .leading
                            )
                            .multilineTextAlignment(.leading)

                        HStack {
                            Text("Cache size")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Text(imageCacheSize)

                            Button("Clear cache") {
                                clearImageCache()
                            }
                        }

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        Text("Error reporting: (may require restart)")
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                            .bold()

                        HStack {
                            Text("Enable Sentry")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Picker("Enable Sentry", selection: $sentryEnabled) {
                                Text("true").tag(
                                    true
                                )
                                Text("false").tag(
                                    false
                                )
                            }
                            .pickerStyle(.inline)
                            .frame(width: geo.size.width * 0.3)
                        }

                        HStack {
                            Text("Sentry DSN")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            TextField("Sentry DSN", text: $sentryDSN)
                                .autocapitalization(.none)
                                .padding(8)
                                .cornerRadius(6)
                                .frame(width: geo.size.width * 0.4)
                        }

                        Text(
                            "When enabled and empty, error reporting is sent to the app's creator"
                        )
                        .foregroundColor(.white)

                        Divider().frame(
                            width: leftSideWidth + geo.size.width * 0.4
                        )

                        HStack {
                            Text("Debug logs")
                                .frame(
                                    width: leftSideWidth,
                                    alignment: .leading
                                )
                                .bold()

                            Button("Clear logs") {
                                appLog.clear()
                            }
                            .frame(
                                width: geo.size.width * 0.4,
                                alignment: .leading
                            )
                        }

                        if appLog.entries.isEmpty {
                            Text("No logs yet.").foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(appLog.entries.suffix(20).reversed())) { entry in
                                    DebugLogRow(
                                        entry: entry,
                                        maxWidth: geo.size.width * 0.6
                                    )
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(40)
                    .onAppear(perform: loadSettings)
                    Spacer() // push everything to center horizontally
                }
            }
        }
    }

    private func saveSettings() {
        let savedUrl = KeychainHelper.saveImmichURL(url: immichURL)
        let savedAuthMethod = KeychainHelper.saveImmichAPIAuthMethod(
            method: immichAuthMethod
        )
        let savedApiKey = KeychainHelper.saveImmichAPIKey(key: immichAuthAPIKey)
        let savedAuthEmail = KeychainHelper.saveImmichAuthEmail(
            email: immichAuthEmail
        )
        let savedAuthPassword = KeychainHelper.saveImmichAuthPassword(
            password: immichAuthPassword
        )

        if !savedUrl || !savedApiKey || !savedAuthMethod || !savedAuthEmail
            || !savedAuthPassword
        {
            errorWhileSaving = true
        } else {
            errorWhileSaving = false
        }

        validateConfig()
    }

    private func loadSettings() {
        immichURL = KeychainHelper.loadImmichURL() ?? ""
        immichAuthMethod = KeychainHelper.loadImmichAPIAuthMethod() ?? .apiKey
        immichAuthAPIKey = KeychainHelper.loadImmichAPIKey() ?? ""
        immichAuthEmail = KeychainHelper.loadImmichAuthEmail() ?? ""
        immichAuthPassword = KeychainHelper.loadImmichAuthPassword() ?? ""

        refreshImageCacheSize()
        validateConfig()
    }

    private func refreshImageCacheSize() {
        Task { @MainActor in
            let bytes = await Task.detached {
                ImageDiskCache.shared.totalSizeBytes()
            }.value
            imageCacheSize = bytes == 0
                ? "empty"
                : ByteCountFormatter.string(
                    fromByteCount: bytes,
                    countStyle: .file
                )
        }
    }

    private func clearImageCache() {
        ImageDiskCache.shared.clear()
        refreshImageCacheSize()
    }

    func validateConfig() {
        configurationError = nil
        connectionTested = false
        connectionWorking = false
        outdatedServer = false

        if !isValidHTTPURL(immichURL) {
            configurationError =
                "wrong Immich URL (maybe missing http:// or https://)"
        }

        Task {
            await testConnection()
        }
    }

    func testConnection() async {
        do {
            _ = try await immichClient.findAlbums(order: .fromOldest)

            connectionTested = true
            connectionWorking = true

            configurationError = nil

            if let version = try? await immichClient.getServerVersion() {
                outdatedServer = version < minimumImmichVersion
            } else {
                outdatedServer = false
            }
        } catch ImmichAPIError.missingConfig {
            connectionTested = false

            configurationErrorColour = .yellow
            configurationError = "caution: missing configuration"
        } catch {
            connectionTested = true
            connectionWorking = false

            configurationErrorColour = .red
            configurationError = "error: \(error.localizedDescription)"
        }
    }
}

private struct DebugLogRow: View {
    let entry: LogEntry
    let maxWidth: CGFloat

    @FocusState private var focused: Bool

    var body: some View {
        Text("[\(entry.date.formatted(date: .omitted, time: .standard))] \(entry.message)")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.red)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(focused ? Color.white.opacity(0.12) : Color.clear)
            .cornerRadius(8)
            .focusable(true)
            .focused($focused)
            .scaleEffect(focused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: focused)
    }
}
