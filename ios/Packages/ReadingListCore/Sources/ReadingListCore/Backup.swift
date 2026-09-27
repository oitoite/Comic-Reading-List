import Foundation

// MARK: - Backup / restore
//
// Exact port of the web app's `backupPayload` / `backupName` (assets/app.js lines
// 1965-1976) and `importJson` (lines 2044-2072).

public enum Backup {

    public struct Payload: Encodable {
        public var version: Int = Schema.version
        public var exportedAt: String
        public var lists: [Playlist]
        public var services: [Service]

        public init(exportedAt: String, lists: [Playlist], services: [Service]) {
            self.exportedAt = exportedAt
            self.lists = lists
            self.services = services
        }
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isoDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Pretty-printed JSON with sorted keys, mirroring `JSON.stringify(payload, null, 2)`.
    public static func export(state: AppState, now: Date = Date()) throws -> Data {
        let payload = Payload(exportedAt: isoTimestamp(now), lists: state.lists, services: state.prefs.services)
        return try JSON.encode(payload, pretty: true)
    }

    public static func fileName(now: Date = Date()) -> String {
        "unlimited-reading-list-\(isoDateOnly(now)).json"
    }

    /// Parses a backup file's bytes into its playlists, migrating a v1 backup on the
    /// way in. `nil` when nothing readable comes out of it.
    public static func importLists(from data: Data) -> [Playlist]? {
        guard let parsed = JSON.parse(data) as? [String: Any] else { return nil }

        let incoming: [Playlist]
        if V1Migration.looksLikeV1(parsed) {
            incoming = V1Migration.migrate(parsed).lists
        } else {
            incoming = Sanitizer.lists(parsed["lists"])
        }
        return incoming.isEmpty ? nil : incoming
    }

    /// Appends each incoming list under a fresh id, appending " (imported)" to the
    /// name when a list with that name already exists, and makes the last appended
    /// list active.
    public static func merge(_ incoming: [Playlist], into state: inout AppState) {
        for var list in incoming {
            list.id = IDs.make()
            if state.lists.contains(where: { $0.name == list.name }) {
                list.name += " (imported)"
            }
            state.lists.append(list)
        }
        if let last = state.lists.last {
            state.activeListId = last.id
        }
    }
}
