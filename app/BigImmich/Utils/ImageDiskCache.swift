import CryptoKit
import Foundation

/// On-disk store for downloaded image bytes (thumbnail / preview / fullsize renditions), so
/// photos we've already fetched are read from local storage instead of over the network on
/// every view. Videos are not stored here.
///
/// Keys are opaque strings (the caller builds them from asset id + size); each maps to one
/// file in a dedicated Caches subdirectory, named by the SHA-256 of the key so any id is
/// filesystem-safe. Writes are async and reads/size/clear are serialized on a single queue,
/// so concurrent callers stay consistent. Living in `Caches` means tvOS may purge it under
/// storage pressure — that's fine, a miss just re-downloads.
final nonisolated class ImageDiskCache: @unchecked Sendable {
    static let shared = ImageDiskCache()

    /// `@AppStorage` key for caching browsing renditions (thumbnail/preview). Defaults to on.
    static let thumbnailsEnabledDefaultsKey = "cacheThumbnails"
    /// `@AppStorage` key for caching the full-size slideshow photos. Defaults to off (large).
    static let fullSizeEnabledDefaultsKey = "cacheFullSizeImages"

    /// Caching of thumbnail/preview renditions. Absent (first launch) counts as enabled.
    static var isThumbnailsEnabled: Bool {
        UserDefaults.standard.object(forKey: thumbnailsEnabledDefaultsKey) as? Bool ?? true
    }

    /// Caching of full-size slideshow images. Absent (first launch) counts as disabled.
    static var isFullSizeImagesEnabled: Bool {
        UserDefaults.standard.bool(forKey: fullSizeEnabledDefaultsKey)
    }

    private let directory: URL
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "nl.slakje.BigImmich.image-disk-cache")

    init(directoryName: String = "ImageCache") {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var dir = caches.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        // Regenerable cache — keep it out of any backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        directory = dir
    }

    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// Returns the stored bytes for `key`, or `nil` on a miss.
    func data(forKey key: String) -> Data? {
        ioQueue.sync {
            try? Data(contentsOf: fileURL(forKey: key))
        }
    }

    /// Persists `data` for `key`. Fire-and-forget so it never blocks the network path.
    func store(_ data: Data, forKey key: String) {
        ioQueue.async { [self] in
            try? data.write(to: fileURL(forKey: key), options: .atomic)
        }
    }

    /// Total bytes currently occupied by the cache on disk.
    func totalSizeBytes() -> Int64 {
        ioQueue.sync {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else {
                return 0
            }
            return urls.reduce(Int64(0)) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + Int64(size)
            }
        }
    }

    /// Removes every cached file.
    func clear() {
        ioQueue.sync {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                return
            }
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
