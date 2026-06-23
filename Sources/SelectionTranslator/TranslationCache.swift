import Foundation

actor TranslationCache {
    static let shared = TranslationCache()

    private struct Entry {
        let value: String
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let maxEntries: Int
    private var entries: [String: Entry] = [:]

    init(ttl: TimeInterval = 10 * 60, maxEntries: Int = 100) {
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    func value(for key: String) -> String? {
        guard let entry = entries[key] else {
            return nil
        }

        if entry.expiresAt <= Date() {
            entries[key] = nil
            return nil
        }

        return entry.value
    }

    func store(_ value: String, for key: String) {
        entries[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
        pruneIfNeeded()
    }

    static func key(text: String, provider: TranslationProvider, apiURL: String, model: String) -> String {
        let normalizedText = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let normalizedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return [provider.rawValue, normalizedAPIURL, normalizedModel, normalizedText].joined(separator: "\u{1F}")
    }

    private func pruneIfNeeded() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }

        guard entries.count > maxEntries else {
            return
        }

        let keysToRemove = entries
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(entries.count - maxEntries)
            .map(\.key)

        for key in keysToRemove {
            entries[key] = nil
        }
    }
}
