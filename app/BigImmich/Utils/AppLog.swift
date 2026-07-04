import Combine
import Foundation

enum LogLevel: String, Codable {
    case info
    case error
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let message: String
    let source: String?
}

final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []

    private let countLimit = 200
    private let storageKey = "debugLogs"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([LogEntry].self, from: data)
        {
            entries = stored
        }
    }

    func log(_ message: String, level: LogLevel, source: String? = nil) {
        let entry = LogEntry(id: UUID(), date: Date(), level: level, message: message, source: source)
        DispatchQueue.main.async { [weak self] in
            self?.append(entry)
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
            self?.persist()
        }
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > countLimit {
            entries.removeFirst(entries.count - countLimit)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
