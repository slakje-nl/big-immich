import Foundation

/// One quality rendition advertised by an HLS master playlist.
public struct HLSVariant: Sendable, Equatable {
    /// The variant index in the server's ladder (the `{variantIndex}` path segment).
    public let index: Int
    public let widthPixels: Int
    public let heightPixels: Int
    /// Advertised peak bitrate in bits/second.
    public let bandwidth: Int
    /// Absolute URL of this variant's media playlist.
    public let playlistURL: URL

    public init(index: Int, widthPixels: Int, heightPixels: Int, bandwidth: Int, playlistURL: URL) {
        self.index = index
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.bandwidth = bandwidth
        self.playlistURL = playlistURL
    }
}

/// A resolved HLS streaming session for one asset: the master playlist to hand AVFoundation for
/// adaptive (Auto) playback, the individual variants for pinned playback / the quality menu, and
/// the auth headers that must ride along on every request.
public struct HLSStream: Sendable {
    public let sessionID: String
    public let masterURL: URL
    public let authHeaders: [String: String]
    public let variants: [HLSVariant]

    public init(sessionID: String, masterURL: URL, authHeaders: [String: String], variants: [HLSVariant]) {
        self.sessionID = sessionID
        self.masterURL = masterURL
        self.authHeaders = authHeaders
        self.variants = variants
    }

    /// The variant whose height best matches a pinned target: the tallest rendition no taller
    /// than `height`, or — if every rendition is taller — the shortest available. `nil` when
    /// there are no variants.
    public func variant(forMaxHeight height: Int) -> HLSVariant? {
        guard !variants.isEmpty else { return nil }
        let atOrBelow = variants.filter { $0.heightPixels <= height }
        if let best = atOrBelow.max(by: { $0.heightPixels < $1.heightPixels }) {
            return best
        }
        return variants.min(by: { $0.heightPixels < $1.heightPixels })
    }

    /// The highest-resolution variant, for a "pin to best" preference.
    public var bestVariant: HLSVariant? {
        variants.max(by: { $0.heightPixels < $1.heightPixels })
    }
}

/// Parses an HLS master playlist body into variants. Pure and side-effect free so it can be
/// unit-tested against captured playlist text.
///
/// Immich advertises each variant as a *relative* URI of the form
/// `{sessionId}/{variantIndex}/playlist.m3u8`, so URIs are resolved against `masterURL` and the
/// session id / variant index are taken from the URI's path components.
public enum HLSPlaylistParser {
    public static func parseVariants(playlist: String, masterURL: URL) -> [HLSVariant] {
        let lines = playlist.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var variants: [HLSVariant] = []

        var index = 0
        while index < lines.count {
            defer { index += 1 }
            let line = lines[index]
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }

            // The URI is the next line that is neither blank nor a tag.
            var uriLine: String?
            var lookahead = index + 1
            while lookahead < lines.count {
                let candidate = lines[lookahead]
                if !candidate.isEmpty, !candidate.hasPrefix("#") {
                    uriLine = candidate
                    break
                }
                lookahead += 1
            }
            guard let uri = uriLine,
                  let playlistURL = URL(string: uri, relativeTo: masterURL)?.absoluteURL
            else { continue }

            let attrs = parseAttributes(line.dropFirst("#EXT-X-STREAM-INF:".count).description)
            let (width, height) = parseResolution(attrs["RESOLUTION"])
            let bandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? 0
            let variantIndex = variantIndex(from: uri) ?? variants.count

            variants.append(
                HLSVariant(
                    index: variantIndex,
                    widthPixels: width,
                    heightPixels: height,
                    bandwidth: bandwidth,
                    playlistURL: playlistURL
                )
            )
        }
        return variants
    }

    /// The session id from a variant URI `{sessionId}/{variantIndex}/playlist.m3u8`.
    public static func sessionID(fromVariantURI uri: String) -> String? {
        let parts = uri.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return String(parts[parts.count - 3])
    }

    private static func variantIndex(from uri: String) -> Int? {
        let parts = uri.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return Int(parts[parts.count - 2])
    }

    /// Splits a comma-separated attribute list, honoring quoted values that contain commas
    /// (e.g. `CODECS="avc1.640028,mp4a.40.2"`).
    private static func parseAttributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current = ""
        var inQuotes = false
        var fields: [String] = []
        for char in text {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            fields.append(current)
        }

        for field in fields {
            guard let eq = field.firstIndex(of: "=") else { continue }
            let key = field[..<eq].trimmingCharacters(in: .whitespaces)
            var value = field[field.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private static func parseResolution(_ value: String?) -> (Int, Int) {
        guard let value else { return (0, 0) }
        let parts = value.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return (0, 0) }
        return (width, height)
    }
}
