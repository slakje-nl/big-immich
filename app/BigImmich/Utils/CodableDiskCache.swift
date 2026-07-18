import CryptoKit
import Foundation

/// On-disk JSON store for small `Codable` values (album lists, per-album duration inputs), so
/// a view can paint instantly from the previous session and refresh in the background instead
/// of blocking on the network every time.
///
/// Each key maps to one file in a dedicated `Caches` subdirectory, named by the SHA-256 of the
/// key so any id is filesystem-safe. Reads/clears are serialized on a single queue and writes
/// are async on that same queue, so concurrent callers stay consistent. Living in `Caches`
/// means tvOS may purge it under storage pressure — that's fine, a miss just re-fetches.
final nonisolated class CodableDiskCache<Value: Codable & Sendable>: @unchecked Sendable {
    private let directory: URL
    private let fileManager = FileManager.default
    private let ioQueue: DispatchQueue

    init(name: String) {
        ioQueue = DispatchQueue(label: "nl.slakje.BigImmich.disk-cache.\(name)")
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var dir = caches.appendingPathComponent("Codable-\(name)", isDirectory: true)
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

    /// Returns the decoded value for `key`, or `nil` on a miss or decode failure.
    func value(forKey key: String) -> Value? {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: fileURL(forKey: key)) else {
                return nil
            }
            return try? JSONDecoder().decode(Value.self, from: data)
        }
    }

    /// Persists `value` for `key`. Fire-and-forget so it never blocks the caller.
    func store(_ value: Value, forKey key: String) {
        ioQueue.async { [self] in
            guard let data = try? JSONEncoder().encode(value) else { return }
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
