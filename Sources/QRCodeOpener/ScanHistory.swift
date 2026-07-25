import Foundation

struct ScanHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let payload: String
    /// Time of the most recent copy — re-copying an existing payload refreshes this rather
    /// than appending a duplicate row.
    var copiedAt: Date

    init(id: UUID = UUID(), payload: String, copiedAt: Date = Date()) {
        self.id = id
        self.payload = payload
        self.copiedAt = copiedAt
    }

    var isURL: Bool { payload.payloadIsURL }
    var subtitle: String { payload.payloadSubtitle }
}

/// Newest-first record of every payload the app has put on the clipboard.
///
/// Stored in `UserDefaults`: the data is small, capped, and this keeps the app free of file
/// access — which matters because the App Store build is sandboxed with no file entitlements.
@MainActor
final class ScanHistory: ObservableObject {
    @Published private(set) var entries: [ScanHistoryEntry] = []

    /// Scanned payloads are potentially sensitive, so the log is bounded rather than
    /// unbounded — old entries fall off instead of accumulating forever.
    private let limit = 200
    private let defaultsKey = "scanHistory"

    init() {
        load()
    }

    /// Records a copy. An existing identical payload moves to the top instead of duplicating.
    func record(_ payload: String) {
        guard !payload.isEmpty else { return }

        if let index = entries.firstIndex(where: { $0.payload == payload }) {
            entries[index].copiedAt = Date()
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(ScanHistoryEntry(payload: payload), at: 0)
        }

        if entries.count > limit {
            entries.removeSubrange(limit...)
        }
        save()
    }

    func remove(_ entry: ScanHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ScanHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
