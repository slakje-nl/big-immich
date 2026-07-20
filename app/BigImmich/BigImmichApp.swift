import KeychainHelper
import Sentry
import SwiftUI

func logError(
    _ error: Error,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    AppLog.shared.log(
        "\(error)",
        level: .error,
        source: "\((file as NSString).lastPathComponent):\(line)"
    )

    let event = Event(level: .error)
    event.message = SentryMessage(formatted: "\(error)")
    event.extra = [
        "file": file,
        "function": function,
        "line": line
    ]

    SentrySDK.capture(event: event)
}

@main
struct BigImmichApp: App {
    @AppStorage("sentryEnabled") private var sentryEnabled: Bool = false
    @AppStorage("sentryDSN") private var sentryDSN: String = ""

    init() {
        Self.applyUITestConfiguration()

        let customSentryDSN = sentryDSN.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        // Error reporting only runs when the user enables it and supplies their own DSN — there
        // is no built-in fallback DSN.
        if sentryEnabled, !customSentryDSN.isEmpty {
            SentrySDK.start { options in
                options.dsn = customSentryDSN

                options.enableAutoSessionTracking = false
                options.tracesSampleRate = 0.0
                options.debug = false
                options.sendDefaultPii = false
                options.attachStacktrace = true
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Seeds or clears Immich credentials from launch arguments so UI tests can
    /// drive a deterministic configuration. No-op during normal use (the flags
    /// are only ever passed by the UI-test runner).
    private static func applyUITestConfiguration() {
        let arguments = ProcessInfo.processInfo.arguments

        let isUITest = arguments.contains("-uiTestReset")
            || arguments.contains("-uiTestImmichURL")
        guard isUITest else { return }

        // The unsigned UI-test build can't use the shared keychain access group,
        // so route credentials through an in-memory store for a deterministic run.
        KeychainHelper.enableInMemoryStore()

        func value(for name: String) -> String? {
            guard let index = arguments.firstIndex(of: name),
                  index + 1 < arguments.count
            else { return nil }
            return arguments[index + 1]
        }

        if arguments.contains("-uiTestReset") {
            _ = KeychainHelper.saveImmichURL(url: "")
            _ = KeychainHelper.saveImmichAPIKey(key: "")
            _ = KeychainHelper.saveImmichAuthEmail(email: "")
            _ = KeychainHelper.saveImmichAuthPassword(password: "")
        }

        if let url = value(for: "-uiTestImmichURL"),
           let apiKey = value(for: "-uiTestImmichAPIKey")
        {
            _ = KeychainHelper.saveImmichURL(url: url)
            _ = KeychainHelper.saveImmichAPIKey(key: apiKey)
            _ = KeychainHelper.saveImmichAPIAuthMethod(method: .apiKey)
        }
    }
}
