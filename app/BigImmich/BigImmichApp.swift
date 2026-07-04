import Sentry
import SwiftUI

func logError(
    _ error: Error,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
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
        if sentryEnabled {
            let customSentryDSN = sentryDSN.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let usedSentryDSN =
                customSentryDSN != ""
                    ? customSentryDSN
                    : "https://3361208ffd59305f7e5c9d0228940679@o118777.ingest.us.sentry.io/4510570198269952"

            SentrySDK.start { options in
                options.dsn = usedSentryDSN

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
}
