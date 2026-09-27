import Foundation

// MARK: - Sanitizer
//
// Every byte that comes from outside the running app — the saved state file, a backup,
// a share link decoded from someone else's URL, a metadata API response — goes through
// here. It takes the loosely typed output of `JSONSerialization` and produces clamped,
// well-formed model values, mirroring the web app's `sanitize*` functions exactly so
// both apps accept the same files.

public enum Sanitizer {

    // MARK: Scalars

    /// Trimmed string clipped to `max`; anything that is not a string becomes "".
    public static func str(_ value: Any?, _ max: Int) -> String {
        guard let s = value as? String else { return "" }
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }

    /// A year between 1900 and 2200 from a number or a numeric string, else nil.
    public static func year(_ value: Any?) -> Int? {
        let n: Int?
        switch value {
        case let i as Int: n = i
        case let d as Double: n = d.isFinite ? Int(d) : nil
        case let s as String: n = Int(s.trimmingCharacters(in: .whitespaces).prefix(6))
        case let ns as NSNumber: n = ns.intValue
        default: n = nil
        }
        guard let y = n, (1900...2200).contains(y) else { return nil }
        return y
    }

    /// Only http(s) links survive — keeps `javascript:` and `data:` URLs out of the UI.
    public static func safeURL(_ value: Any?, _ max: Int = Limits.urlLength) -> String {
        guard let s = value as? String else { return "" }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isHTTP(trimmed) else { return "" }
        return String(trimmed.prefix(max))
    }

    public static func isHTTP(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    public static func rating(_ value: Any?) -> Int {
        let n: Int
        switch value {
        case let i as Int: n = i
        case let d as Double: n = d.isFinite ? Int(d) : 0
        case let s as String: n = Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
        case let ns as NSNumber: n = ns.intValue
        default: n = 0
        }
        return min(5, max(0, n))
    }

    public static func bool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let d as Double: return d != 0
        case let s as String: return !s.isEmpty
        case let ns as NSNumber: return ns.boolValue
        default: return false
        }
    }

    /// Milliseconds since the epoch, or `fallback` when the value is not a number.
    public static func millis(_ value: Any?, fallback: Double) -> Double {
        switch value {
        case let d as Double where d.isFinite: return d
        case let i as Int: return Double(i)
        case let ns as NSNumber: return ns.doubleValue
        default: return fallback
        }
    }

    public static func id(_ value: Any?) -> String {
        if let s = value as? String, !s.isEmpty { return String(s.prefix(64)) }
        return IDs.make()
    }

    /// A known service id, or `fallback`. "" on an entry means "inherit the playlist default".
    public static func serviceID(_ value: Any?, fallback: String = "") -> String {
        let id = str(value, 20)
        return Service.isKnownID(id) ? id : fallback
    }

    // MARK: Model values

    public static func issues(_ raw: Any?) -> [Issue] {
        var out: [Issue] = []
        if let array = raw as? [Any] {
            for item in array.prefix(Limits.maxIssues) {
                if let label = item as? String {
                    out.append(Issue(label: str(label, Limits.labelLength)))
                } else if let dict = item as? [String: Any] {
                    out.append(Issue(label: str(dict["label"], Limits.labelLength),
                                     done: bool(dict["done"]),
                                     url: safeURL(dict["url"])))
                }
            }
        }
        // Every entry owns at least one tickable issue, so progress is never 0 of 0.
        return out.isEmpty ? [Issue()] : out
    }

    public static func tags(_ raw: Any?) -> [String] {
        guard let array = raw as? [Any] else { return [] }
        return array.map { str($0, Limits.labelLength) }.filter { !$0.isEmpty }.prefix(Limits.maxTags).map { $0 }
    }

    public static func entry(_ raw: Any?) -> Entry {
        let e = raw as? [String: Any] ?? [:]
        let series = str(e["series"], Limits.nameLength)
        return Entry(
            id: id(e["id"]),
            series: series.isEmpty ? "Untitled" : series,
            title: str(e["title"], Limits.nameLength),
            issues: issues(e["issues"]),
            started: bool(e["started"]),
            writer: str(e["writer"], Limits.nameLength),
            artist: str(e["artist"], Limits.nameLength),
            publisher: str(e["publisher"], 120),
            year: year(e["year"]),
            service: serviceID(e["service"]),
            url: safeURL(e["url"]),
            cover: safeURL(e["cover"]),
            tags: tags(e["tags"]),
            notes: str(e["notes"], Limits.notesLength),
            rating: rating(e["rating"]),
            addedAt: millis(e["addedAt"], fallback: Timestamps.now())
        )
    }

    /// Accepts both v2 `entries` and v1 `items` arrays (the latter already migrated).
    public static func lists(_ raw: Any?) -> [Playlist] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { item -> Playlist? in
            guard let l = item as? [String: Any] else { return nil }
            let entriesRaw = (l["entries"] as? [Any]) ?? (l["items"] as? [Any]) ?? []
            let name = str(l["name"], Limits.listNameLength)
            return Playlist(
                id: id(l["id"]),
                name: name.isEmpty ? "Untitled list" : name,
                service: serviceID(l["service"], fallback: Service.marvelUnlimitedID),
                createdAt: millis(l["createdAt"], fallback: Timestamps.now()),
                entries: entriesRaw.map(entry)
            )
        }
    }

    /// Always returns the three known services in order; stored names and templates win,
    /// except a template equal to a superseded default, which moves on to the current one.
    public static func services(_ raw: Any?) -> [Service] {
        var byID: [String: (name: String, template: String)] = [:]
        if let array = raw as? [Any] {
            for item in array {
                guard let s = item as? [String: Any] else { continue }
                let id = str(s["id"], 20)
                if !id.isEmpty {
                    byID[id] = (str(s["name"], 60), safeURL(s["template"], Limits.templateLength))
                }
            }
        }
        return Service.defaults.map { d in
            let found = byID[d.id]
            var template = (found?.template).flatMap { $0.isEmpty ? nil : $0 } ?? d.template
            if (Service.supersededTemplates[d.id] ?? []).contains(template) { template = d.template }
            let name = (found?.name).flatMap { $0.isEmpty ? nil : $0 } ?? d.name
            return Service(id: d.id, name: name, template: template)
        }
    }

    public static func prefs(_ raw: Any?) -> Prefs {
        let p = raw as? [String: Any] ?? [:]
        let themeRaw = str(p["theme"], 20)
        return Prefs(
            theme: Theme(rawValue: themeRaw) ?? .system,
            sort: EntrySortOrder(rawValue: str(p["sort"], 20)) ?? .order,
            view: ViewMode(rawValue: str(p["view"], 20)) ?? .list,
            metaApi: safeURL(p["metaApi"], 300),
            backedUpAt: millis(p["backedUpAt"], fallback: 0),
            services: services(p["services"])
        )
    }

    /// The web app's `finalize`: a complete, valid state from any v2-shaped object.
    /// Guarantees at least one playlist and a valid `activeListId`.
    public static func state(_ raw: Any?) -> AppState {
        let s = raw as? [String: Any] ?? [:]
        var lists = self.lists(s["lists"])
        if lists.isEmpty { lists = AppState.blank().lists }
        let requested = s["activeListId"] as? String
        let active = lists.contains { $0.id == requested } ? requested! : lists[0].id
        return AppState(lists: lists, activeListId: active, prefs: prefs(s["prefs"]))
    }
}

// MARK: - JSON helpers

public enum JSON {
    /// Parses text into Foundation objects; nil when it is not JSON.
    public static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public static func parse(_ text: String) -> Any? {
        parse(Data(text.utf8))
    }

    /// Encodes a model in a stable key order so diffs and share links are deterministic.
    public static func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        return try encoder.encode(value)
    }
}
