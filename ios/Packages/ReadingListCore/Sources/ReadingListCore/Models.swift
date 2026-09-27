import Foundation

// MARK: - Schema
//
// These types mirror the web app's `longbox.playlists.v2` JSON exactly, so a backup
// written by the site imports into the app and vice versa. Timestamps are milliseconds
// since the epoch (JavaScript's `Date.now()`), ids are opaque strings.
//
// Decoding is deliberately NOT synthesized: anything that comes from a file, a share
// link or another device is run through `Sanitizer`, which accepts sloppy input
// (`year: ""`, missing keys, string issues) and clamps every field. Encoding is
// synthesized and emits exactly the shape the web app writes.

public enum Schema {
    public static let version = 2
}

public enum Limits {
    /// Per entry — stops `1-99999` from hanging the app.
    public static let maxIssues = 500
    public static let maxBulkLines = 500
    public static let maxShareEntries = 500
    public static let maxTags = 20
    public static let labelLength = 40
    public static let nameLength = 200
    public static let listNameLength = 80
    public static let notesLength = 2000
    public static let urlLength = 2000
    public static let templateLength = 500
    /// Share URLs past this tend to be truncated by chat apps and mail clients.
    public static let shareUrlWarning = 8000
}

// MARK: - Issue

public struct Issue: Encodable, Hashable, Sendable {
    public var label: String
    public var done: Bool
    /// A pasted permalink for this one issue. Empty means "none".
    public var url: String

    public init(label: String = "", done: Bool = false, url: String = "") {
        self.label = label
        self.done = done
        self.url = url
    }
}

// MARK: - Entry (a run or arc, not a single issue)

public struct Entry: Encodable, Hashable, Identifiable, Sendable {
    public var id: String
    public var series: String
    /// Arc name. Empty when the entry is just "a run of the series".
    public var title: String
    /// Never empty: an unnumbered book is one issue with an empty label.
    public var issues: [Issue]
    /// Explicit "I have started this" even with no issue ticked yet.
    public var started: Bool
    public var writer: String
    public var artist: String
    public var publisher: String
    public var year: Int?
    /// Service id, or "" to inherit the playlist default.
    public var service: String
    /// Direct link for the whole entry. Empty means "none".
    public var url: String
    public var cover: String
    public var tags: [String]
    public var notes: String
    /// 0 (unrated) through 5.
    public var rating: Int
    /// Milliseconds since the epoch.
    public var addedAt: Double

    public init(id: String = IDs.make(), series: String, title: String = "", issues: [Issue] = [Issue()],
                started: Bool = false, writer: String = "", artist: String = "", publisher: String = "",
                year: Int? = nil, service: String = "", url: String = "", cover: String = "",
                tags: [String] = [], notes: String = "", rating: Int = 0,
                addedAt: Double = Timestamps.now()) {
        self.id = id
        self.series = series
        self.title = title
        self.issues = issues.isEmpty ? [Issue()] : issues
        self.started = started
        self.writer = writer
        self.artist = artist
        self.publisher = publisher
        self.year = year
        self.service = service
        self.url = url
        self.cover = cover
        self.tags = tags
        self.notes = notes
        self.rating = rating
        self.addedAt = addedAt
    }

    public var addedDate: Date { Timestamps.date(fromMillis: addedAt) }

    /// One issue with no label: a graphic novel or one-shot.
    public var isSingleBook: Bool { issues.count == 1 && issues[0].label.isEmpty }

    /// "Series · Arc" or just the series.
    public var displayName: String { title.isEmpty ? series : "\(series) · \(title)" }
}

// MARK: - Playlist

public struct Playlist: Encodable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Default service id for entries that do not override it.
    public var service: String
    /// Milliseconds since the epoch.
    public var createdAt: Double
    public var entries: [Entry]

    public init(id: String = IDs.make(), name: String, service: String = Service.marvelUnlimitedID,
                createdAt: Double = Timestamps.now(), entries: [Entry] = []) {
        self.id = id
        self.name = name
        self.service = service
        self.createdAt = createdAt
        self.entries = entries
    }

    public var createdDate: Date { Timestamps.date(fromMillis: createdAt) }
}

// MARK: - Service

public struct Service: Encodable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Search template; `{q}`, `{series}` and `{issue}` are substituted. Must be http(s).
    public var template: String

    public init(id: String, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    public static let marvelUnlimitedID = "mu"
    public static let dcUniverseInfiniteID = "dcui"
    public static let otherID = "other"

    /// Search templates stay editable in the app. The Marvel one is marvel.com's real
    /// comics search; DC's could not be verified, so a site-scoped web search stands in.
    public static let defaults: [Service] = [
        Service(id: marvelUnlimitedID, name: "Marvel Unlimited",
                template: "https://www.marvel.com/search?content_type=comics&offset=0&query={q}"),
        Service(id: dcUniverseInfiniteID, name: "DC Universe Infinite",
                template: "https://duckduckgo.com/?q=site%3Adcuniverseinfinite.com+{q}"),
        Service(id: otherID, name: "Other", template: "https://duckduckgo.com/?q={q}")
    ]

    /// Defaults that shipped in earlier builds. A stored template still matching one of
    /// these was never edited by hand, so it is safe to move on to the current default.
    public static let supersededTemplates: [String: [String]] = [
        marvelUnlimitedID: ["https://duckduckgo.com/?q=site%3Amarvel.com+{q}"]
    ]

    public static func isKnownID(_ id: String) -> Bool {
        defaults.contains { $0.id == id }
    }
}

// MARK: - Preferences

public enum EntrySortOrder: String, Encodable, CaseIterable, Sendable {
    case order, added, series, title, progress, year, rating

    public var displayName: String {
        switch self {
        case .order: return "Reading order"
        case .added: return "Recently added"
        case .series: return "Series"
        case .title: return "Arc title"
        case .progress: return "Progress"
        case .year: return "Year"
        case .rating: return "Rating"
        }
    }
}

public enum ViewMode: String, Encodable, CaseIterable, Sendable {
    case list, grid
}

/// The web app only knows light and dark; `system` is the iOS default and is written
/// as `dark` when a backup is exported for the web.
public enum Theme: String, Encodable, CaseIterable, Sendable {
    case system, light, dark
}

public struct Prefs: Encodable, Hashable, Sendable {
    public var theme: Theme
    public var sort: EntrySortOrder
    public var view: ViewMode
    /// Base URL of the comic metadata API; empty means the built-in default.
    public var metaApi: String
    /// Milliseconds since the epoch of the last "Save a copy"; 0 = never.
    public var backedUpAt: Double
    public var services: [Service]

    public init(theme: Theme = .system, sort: EntrySortOrder = .order, view: ViewMode = .list,
                metaApi: String = "", backedUpAt: Double = 0, services: [Service] = Service.defaults) {
        self.theme = theme
        self.sort = sort
        self.view = view
        self.metaApi = metaApi
        self.backedUpAt = backedUpAt
        self.services = services
    }
}

// MARK: - Whole state

public struct AppState: Encodable, Hashable, Sendable {
    public var version: Int
    public var lists: [Playlist]
    public var activeListId: String?
    public var prefs: Prefs

    public init(version: Int = Schema.version, lists: [Playlist], activeListId: String?, prefs: Prefs = Prefs()) {
        self.version = version
        self.lists = lists
        self.activeListId = activeListId
        self.prefs = prefs
    }

    /// One empty playlist, Marvel Unlimited by default.
    public static func blank() -> AppState {
        let list = Playlist(name: "My reading list")
        return AppState(lists: [list], activeListId: list.id)
    }
}

// MARK: - Derived status

public enum ReadStatus: String, CaseIterable, Sendable {
    case unread, reading, finished

    public var displayName: String {
        switch self {
        case .unread: return "Not started"
        case .reading: return "In progress"
        case .finished: return "Finished"
        }
    }
}

// MARK: - Small utilities shared by the models

public enum IDs {
    /// Same shape as the web app's ids: `c` + base36 time + 6 random base36 chars.
    public static func make() -> String {
        let time = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let random = String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        return "c" + time + random
    }
}

public enum Timestamps {
    public static func now() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded()
    }

    public static func date(fromMillis ms: Double) -> Date {
        Date(timeIntervalSince1970: ms / 1000)
    }
}
