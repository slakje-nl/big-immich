import Combine
import ImmichAPI
import KeychainHelper
import SwiftUI

/// The left-sidebar categories. Moving focus onto one swaps the detail pane.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case connection
    case slideshow
    case controls
    case performance
    case diagnostics
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .slideshow: "Slideshow"
        case .controls: "Controls"
        case .performance: "Performance"
        case .diagnostics: "Diagnostics"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .connection: "link"
        case .slideshow: "photo.on.rectangle"
        case .controls: "av.remote"
        case .performance: "speedometer"
        case .diagnostics: "ladybug"
        case .about: "info.circle"
        }
    }
}

/// One design system for the settings screen: fonts, sizes and the two colour sets — one for a
/// row at rest (on the dark ground) and one for a focused/highlighted row (on the light card).
enum SettingsDesign {
    static let titleFont = Font.body
    static let subtitleFont = Font.footnote
    static let valueFont = Font.body
    static let sectionFont = Font.caption

    // At rest (dark ground)
    static let title = Color.white
    static let subtitle = Color.white.opacity(0.55)
    static let value = Color.white.opacity(0.75)

    // Focused / highlighted (light card)
    static let titleFocused = Color.black
    static let subtitleFocused = Color.black.opacity(0.6)
    static let valueFocused = Color.black.opacity(0.7)

    static let rowMinHeight: CGFloat = 78
    static let cardFill = Color.white.opacity(0.05)
    static let fieldFill = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.08)
    static let cornerRadius: CGFloat = 14
}

/// Focus treatment for a right-side control (dropdown value, toggle switch, stepper button): a
/// rounded fill + gentle lift when focused, so the control — not the whole row — highlights.
private struct ControlFocusStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white.opacity(0.18) : Color.clear)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}

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
    @AppStorage("slideshowPreloadVideos") private var slideshowPreloadVideos: Bool = true
    @AppStorage(ImageDiskCache.thumbnailsEnabledDefaultsKey) private var cacheThumbnails: Bool = true
    @AppStorage(ImageDiskCache.fullSizeEnabledDefaultsKey) private var cacheFullSizeImages: Bool = false
    @State private var imageCacheSize: String = "…"

    // error reporting
    @AppStorage("sentryEnabled") private var sentryEnabled: Bool = false
    @AppStorage("sentryDSN") private var sentryDSN: String = ""

    @State private var errorWhileSaving: Bool = false

    @State private var configurationError: String?
    @State private var configurationErrorColour: Color = .white
    @State private var connectionTested: Bool = false
    @State private var connectionWorking: Bool = true

    @ObservedObject private var appLog = AppLog.shared
    @State private var outdatedServer = false

    @State private var selectedCategory: SettingsCategory = .connection
    /// The sidebar is a single focus target (not one-per-category), so left from the detail always
    /// returns here — to the selected category — instead of the geometrically nearest row.
    @FocusState private var sidebarFocused: Bool
    /// Which Controls-page row is focused, mirrored onto the on-screen remote so the highlighted
    /// action lights up its button/gesture there too.
    @FocusState private var focusedControl: RemoteControl?

    var immichClient: ImmichClientProtocol = ImmichClient.shared
    var onExit: () -> Void = {}

    private let minimumImmichVersion = ServerVersion(major: 3, minor: 0, patch: 1)

    private var showProgressBar: Binding<Bool> {
        Binding(
            get: { slideshowShowProgressBar == .always },
            set: { slideshowShowProgressBar = $0 ? .always : .never }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(SettingsDesign.divider)
                .frame(width: 1)
                .ignoresSafeArea()
            detailPane
        }
        .onAppear {
            loadSettings()
            sidebarFocused = true
        }
        .onExitCommand {
            // Two-stage back: from a detail control, return to the sidebar; from the sidebar,
            // leave Settings.
            if sidebarFocused {
                onExit()
            } else {
                sidebarFocused = true
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title2).bold()
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            ForEach(SettingsCategory.allCases) { category in
                categoryRow(category)
            }

            Spacer()

            goBackHint
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .focusable()
        .focused($sidebarFocused)
        // The whole sidebar is one focus target: up/down change the category. Right/left are left to
        // the focus engine — right enters the detail's `.focusSection()` (landing on its first
        // control in one clean move), left returns here.
        .onMoveCommand { direction in
            switch direction {
            case .up: moveCategory(by: -1)
            case .down: moveCategory(by: 1)
            default: break
            }
        }
    }

    private func categoryRow(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        // The selected row highlights white while the sidebar is focused, grey when focus is in
        // the detail pane — so you always see where you are.
        let background: Color = isSelected
            ? (sidebarFocused ? .white : Color.white.opacity(0.14))
            : .clear
        return HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.body)
                .frame(width: 26)
            Text(category.title)
                .font(.body)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .foregroundColor(isSelected && sidebarFocused ? .black : .white)
        .background(RoundedRectangle(cornerRadius: 12).fill(background))
        .animation(.easeInOut(duration: 0.12), value: sidebarFocused)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private func moveCategory(by offset: Int) {
        let all = SettingsCategory.allCases
        guard let index = all.firstIndex(of: selectedCategory) else { return }
        let next = index + offset
        guard all.indices.contains(next) else { return }
        selectedCategory = all[next]
    }

    private var goBackHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.backward")
            Text("Back to leave")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Detail

    private var detailPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedCategory {
                case .connection: connectionDetail
                case .slideshow: slideshowDetail
                case .controls: controlsDetail
                case .performance: performanceDetail
                case .diagnostics: diagnosticsDetail
                case .about: aboutDetail
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Treat the detail as one focus region so a right-press from the sidebar lands on its first
        // control directly, and a left-press returns to the sidebar.
        .focusSection()
    }

    // MARK: - Connection

    @ViewBuilder
    private var connectionDetail: some View {
        if errorWhileSaving {
            Text("Error saving settings!").foregroundColor(.red).bold()
        }

        card {
            pickerRow(
                "Auth method",
                value: $immichAuthMethod,
                options: [("API key (recommended)", .apiKey), ("email & password", .emailAndPassword)],
                first: true,
                onChange: saveSettings
            )
            rowDivider
            EditableFieldRow(
                title: "Immich URL",
                placeholder: "https://immich.example.com",
                accessibilityID: "immichURLField",
                text: $immichURL,
                onChange: saveSettings
            )
            rowDivider
            switch immichAuthMethod {
            case .apiKey:
                EditableFieldRow(
                    title: "API key",
                    subtitle: "Needs album.read, asset.view, asset.download.",
                    placeholder: "Enter API key",
                    secure: true,
                    accessibilityID: "apiKeyField",
                    text: $immichAuthAPIKey,
                    onChange: saveSettings
                )
            case .emailAndPassword:
                EditableFieldRow(
                    title: "Email",
                    placeholder: "Enter email",
                    text: $immichAuthEmail,
                    onChange: saveSettings
                )
                rowDivider
                EditableFieldRow(
                    title: "Password",
                    placeholder: "Enter password",
                    secure: true,
                    text: $immichAuthPassword,
                    onChange: saveSettings
                )
            }
        }

        footnote("Tip: paste your \(immichAuthMethod == .apiKey ? "API key" : "password") using the Apple TV remote app on your iPhone.")

        connectionStatus
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if let configurationError {
            statusChip(configurationError, color: configurationErrorColour)
        } else if connectionTested {
            if connectionWorking {
                statusChip("Connection to Immich works", color: .green)
                if outdatedServer {
                    footnote("This app is designed for Immich \(minimumImmichVersion.displayString) or newer. Updating Immich is recommended.", color: .yellow)
                }
            } else {
                statusChip("Couldn't connect to Immich", color: .red)
            }
        }
    }

    // MARK: - Slideshow

    private var slideshowDetail: some View {
        card {
            pickerRow("Slide interval", value: $slideshowInterval, options: slideIntervalOptions, first: true)
            rowDivider
            pickerRow(
                "Direction",
                value: $slideshowDirection,
                options: [
                    ("oldest → newest", .oldestToNewest),
                    ("newest → oldest", .newestToOldest),
                    ("randomized", .randomized)
                ]
            )
            rowDivider
            pickerRow(
                "When an album ends",
                value: $slideshowOnceEndedAction,
                options: [
                    ("stop and show a message", .stopAndNotify),
                    ("start again", .startAgain),
                    ("load another album", .loadAnotherAlbum)
                ]
            )
            if slideshowOnceEndedAction == .loadAnotherAlbum {
                rowDivider
                pickerRow(
                    "Next album",
                    value: $slideshowOnceEndedAnotherAlbumSelection,
                    options: [("older", .older), ("newer", .newer), ("random", .random)]
                )
            }
            rowDivider
            toggleRow("Show progress bar", isOn: showProgressBar)
        }
    }

    // MARK: - Controls

    private var controlsDetail: some View {
        HStack(alignment: .top, spacing: 56) {
            RemoteDiagramView(highlight: focusedControl)
                .frame(height: 820)

            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("What each control does")
                card {
                    controlRow(.up, title: "Up") { staticControlValue("open the options menu") }
                    rowDivider
                    controlRow(.down, title: "Down") { staticControlValue("show the progress bar (movies only)") }
                    rowDivider
                    editableControlRow(.left, title: "Left", value: $slideshowLeftAction)
                    rowDivider
                    editableControlRow(.right, title: "Right", value: $slideshowRightAction)
                    rowDivider
                    controlRow(.back, title: "Back") { staticControlValue("exit · close the menu") }
                    rowDivider
                    controlRow(.playPause, title: "Play / pause") { staticControlValue("pause or resume") }
                }
                footnote("Left and right scrub the video while it is paused.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var directionOptions: [(String, SlideshowAction)] {
        [("next asset", .goToNext), ("previous asset", .goToPrevious)]
    }

    /// 1–10s in 1s steps, then 12/15/20s, then every 5s up to 60s.
    private var slideIntervalOptions: [(String, Int)] {
        let values = Array(1 ... 10) + [12, 15, 20] + stride(from: 25, through: 60, by: 5)
        return values.map { ("\($0) second\($0 == 1 ? "" : "s")", $0) }
    }

    /// A Controls-page row: an icon + gesture/button name, and its effect on the right. The whole
    /// row is focusable so highlighting it lights up the matching control on the remote.
    private func controlRow(_ control: RemoteControl, title: String, @ViewBuilder value: () -> some View) -> some View {
        controlRowBody(control, title: title, value: value)
            .focusable()
            .focused($focusedControl, equals: control)
    }

    /// A Controls-page row whose effect is a configurable Left/Right action. The dropdown carries
    /// the focus (and thus the remote highlight).
    private func editableControlRow(_ control: RemoteControl, title: String, value: Binding<SlideshowAction>) -> some View {
        controlRowBody(control, title: title) {
            directionMenu(value)
                .focused($focusedControl, equals: control)
        }
    }

    private func controlRowBody(_ control: RemoteControl, title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 18) {
            Image(systemName: control.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text(title).font(SettingsDesign.titleFont).foregroundColor(SettingsDesign.title)
            Spacer(minLength: 24)
            value()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(minHeight: SettingsDesign.rowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(focusedControl == control ? Color.white.opacity(0.10) : .clear)
        )
        .animation(.easeInOut(duration: 0.12), value: focusedControl)
    }

    private func staticControlValue(_ text: String) -> some View {
        Text(text).font(SettingsDesign.valueFont).foregroundColor(SettingsDesign.value)
    }

    private func directionMenu(_ value: Binding<SlideshowAction>) -> some View {
        Menu {
            ForEach(directionOptions, id: \.1) { option in
                Button {
                    value.wrappedValue = option.1
                } label: {
                    if value.wrappedValue == option.1 {
                        Label(option.0, systemImage: "checkmark")
                    } else {
                        Text(option.0)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(directionOptions.first { $0.1 == value.wrappedValue }?.0 ?? "")
                Image(systemName: "chevron.down").font(.caption)
            }
        }
    }

    // MARK: - Performance

    private var performanceDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                pickerRow(
                    "Photo quality",
                    value: $slideshowImageQuality,
                    options: [
                        ("thumbnail", .thumbnail),
                        ("preview", .preview),
                        ("full-size (recommended)", .fullsize),
                        ("original", .original)
                    ],
                    first: true
                )
                rowDivider
                toggleRow(
                    "Preload videos",
                    subtitle: "Warms the next video for a faster start; turn off if it causes playback issues.",
                    isOn: $slideshowPreloadVideos
                )
            }

            sectionHeader("On-disk cache")
            card {
                toggleRow("Cache thumbnails", isOn: $cacheThumbnails)
                rowDivider
                toggleRow(
                    "Cache full-size photos",
                    subtitle: "Speeds up repeat views but uses more storage.",
                    isOn: $cacheFullSizeImages
                )
                rowDivider
                rowShell("Cache size") {
                    HStack(spacing: 16) {
                        Text(imageCacheSize).font(SettingsDesign.valueFont).foregroundColor(SettingsDesign.value)
                        Button("Clear", action: clearImageCache)
                            .buttonStyle(ControlFocusStyle())
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Error reporting (may require restart)")
            card {
                toggleRow("Enable error reporting to Sentry", isOn: $sentryEnabled, first: true)
                if sentryEnabled {
                    rowDivider
                    EditableFieldRow(title: "Sentry DSN", placeholder: "Enter a DSN", text: $sentryDSN)
                }
            }

            sectionHeader("Debug logs")
            HStack {
                Text("Recent errors captured on this device").font(.body)
                Spacer()
                Button("Clear logs") { appLog.clear() }
            }

            if appLog.entries.isEmpty {
                Text("No logs yet.").foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(appLog.entries.suffix(20).reversed())) { entry in
                        DebugLogRow(entry: entry, maxWidth: 900)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("App")
            card {
                rowShell("App version") {
                    Text(appVersion).font(SettingsDesign.valueFont).foregroundColor(SettingsDesign.value)
                }
                rowDivider
                rowShell("Designed for Immich") {
                    Text("\(minimumImmichVersion.displayString) or newer")
                        .font(SettingsDesign.valueFont).foregroundColor(SettingsDesign.value)
                }
            }

            sectionHeader("Feedback")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 24) {
                        Text("Project website").font(SettingsDesign.titleFont).foregroundColor(SettingsDesign.title)
                        Spacer(minLength: 24)
                        Text("github.com/slakje-nl/big-immich")
                            .font(SettingsDesign.valueFont).foregroundColor(SettingsDesign.value)
                    }
                    Text("Found a bug or a missing feature?\nOpen an issue there to improve the app.")
                        .font(SettingsDesign.subtitleFont)
                        .foregroundColor(SettingsDesign.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }

            footnote("This is a community app that displays Immich photo & video slideshows on Apple TV. It is not affiliated with Immich.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Reusable rows

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(SettingsDesign.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One consistent row shape: a static title (+ optional description) on the left, and a
    /// focusable control on the right — so a dropdown, toggle, stepper and text field all line up
    /// and highlight the *control*, not the whole row (matching the text-field rows).
    private func rowShell(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsDesign.titleFont).foregroundColor(SettingsDesign.title)
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsDesign.subtitleFont)
                        .foregroundColor(SettingsDesign.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 24)
            control()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(minHeight: SettingsDesign.rowMinHeight)
    }

    /// A dropdown (native Menu) — the value on the right opens a list of options.
    private func pickerRow<Value: Hashable>(
        _ title: String,
        subtitle: String? = nil,
        value: Binding<Value>,
        options: [(String, Value)],
        first _: Bool = false,
        onChange: (() -> Void)? = nil
    ) -> some View {
        rowShell(title, subtitle: subtitle) {
            Menu {
                ForEach(options, id: \.1) { option in
                    Button {
                        value.wrappedValue = option.1
                        onChange?()
                    } label: {
                        if value.wrappedValue == option.1 {
                            Label(option.0, systemImage: "checkmark")
                        } else {
                            Text(option.0)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(options.first { $0.1 == value.wrappedValue }?.0 ?? "")
                    Image(systemName: "chevron.down").font(.caption)
                }
            }
        }
    }

    /// A boolean toggle — a focusable switch on the right, flipped with the select button.
    private func toggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, first _: Bool = false) -> some View {
        rowShell(title, subtitle: subtitle) {
            Button { isOn.wrappedValue.toggle() } label: {
                switchGraphic(isOn.wrappedValue)
            }
            .buttonStyle(ControlFocusStyle())
        }
    }

    private func switchGraphic(_ isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? Color.green : Color.white.opacity(0.25))
            .frame(width: 52, height: 30)
            .overlay(Circle().fill(.white).padding(3), alignment: isOn ? .trailing : .leading)
    }

    private var rowDivider: some View {
        Rectangle().fill(SettingsDesign.divider).frame(height: 1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SettingsDesign.sectionFont).fontWeight(.semibold)
            .tracking(1.1)
            .foregroundColor(.secondary)
            .padding(.leading, 6)
            .padding(.top, 6)
    }

    private func footnote(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text).font(.body).foregroundColor(color)
    }

    // MARK: - Persistence & validation

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
                AppCaches.totalSizeBytes()
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
        AppCaches.clear()
        refreshImageCacheSize()
    }

    func validateConfig() {
        configurationError = nil
        connectionTested = false
        connectionWorking = false
        outdatedServer = false

        if !isValidHTTPURL(immichURL) {
            configurationError =
                "Wrong Immich URL (maybe missing http:// or https://)"
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
            configurationError = "Caution: missing configuration"
        } catch {
            connectionTested = true
            connectionWorking = false

            configurationErrorColour = .red
            configurationError = "Error: \(error.localizedDescription)"
        }
    }
}

/// A settings row whose value is entered with the on-screen keyboard. It's a real text field, so a
/// single click opens the keyboard directly (no intermediate "edit" step). Styled as a light pill;
/// the row is a touch taller than the others to give the field room to breathe.
private struct EditableFieldRow: View {
    let title: String
    var subtitle: String?
    var placeholder: String = ""
    var secure: Bool = false
    var accessibilityID: String?
    @Binding var text: String
    var onChange: () -> Void = {}

    private let fieldWidth: CGFloat = 720

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsDesign.titleFont).foregroundColor(SettingsDesign.title)
                if let subtitle {
                    Text(subtitle)
                        .font(SettingsDesign.subtitleFont)
                        .foregroundColor(SettingsDesign.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 24)
            field
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .accessibilityIdentifier(accessibilityID ?? "")
                .frame(width: fieldWidth)
                .onChange(of: text) { _, _ in onChange() }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(minHeight: SettingsDesign.rowMinHeight + 12)
    }

    @ViewBuilder private var field: some View {
        if secure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
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
