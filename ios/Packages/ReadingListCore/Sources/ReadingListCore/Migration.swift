import Foundation

// MARK: - v1 migration
//
// Exact port of the web app's `migrateItem` / `migrateV1` (assets/app.js lines
// 285-335) plus the `looksV1` check inlined in `importJson` (line 2050-2052).
//
// A v1 item was a single comic; a v2 entry is a run or arc. The old title becomes
// the arc name only when a series was filled in, otherwise it *is* the series.
//
// Rather than re-deriving every field rule `Sanitizer.entry`/`Sanitizer.lists`
// already encode, this builds the same loosely-typed intermediate object the web
// app's `migrateItem` builds (right before its own call to `sanitizeEntry`) and
// hands the whole v2-shaped tree to `Sanitizer.state`, exactly as `finalize(migrateV1(parsed))`
// does on the JS side.

public enum V1Migration {

    public static func looksLikeV1(_ raw: Any?) -> Bool {
        guard let dict = raw as? [String: Any] else { return false }
        if isOne(dict["version"]) { return true }
        if let lists = dict["lists"] as? [Any] {
            for item in lists {
                if let l = item as? [String: Any], l["items"] is [Any] { return true }
            }
        }
        return false
    }

    public static func migrate(_ raw: Any?) -> AppState {
        let parsed = raw as? [String: Any] ?? [:]
        let listsRaw = parsed["lists"] as? [Any] ?? []
        let prefsRaw = parsed["prefs"] as? [String: Any] ?? [:]

        var migratedLists: [Any] = []
        for item in listsRaw {
            guard let l = item as? [String: Any] else { continue }
            let itemsRaw = l["items"] as? [Any] ?? []
            let entries = itemsRaw.map { migrateItemDict($0) }
            var out: [String: Any] = [:]
            out["id"] = l["id"] ?? NSNull()
            out["name"] = l["name"] ?? NSNull()
            out["service"] = Service.marvelUnlimitedID
            out["createdAt"] = l["createdAt"] ?? NSNull()
            out["entries"] = entries
            migratedLists.append(out)
        }

        let themeRaw = Sanitizer.str(prefsRaw["theme"], 20)
        let viewRaw = Sanitizer.str(prefsRaw["view"], 20)

        var state: [String: Any] = [:]
        state["version"] = Schema.version
        state["lists"] = migratedLists
        if let active = parsed["activeListId"] as? String {
            state["activeListId"] = active
        }
        state["prefs"] = [
            "theme": themeRaw == "light" ? "light" : "dark",
            "sort": "order",
            "view": viewRaw == "grid" ? "grid" : "list",
            "metaApi": "",
            "backedUpAt": 0
        ] as [String: Any]

        return Sanitizer.state(state)
    }

    /// The pre-`sanitizeEntry` object `migrateItem` builds for one old v1 item.
    private static func migrateItemDict(_ raw: Any?) -> [String: Any] {
        let it = raw as? [String: Any] ?? [:]
        let oldSeries = Sanitizer.str(it["series"], 200)
        let oldTitle = Sanitizer.str(it["title"], 200)

        let parsed = IssueSpec.parse(issueSpecString(it["issue"]))
        let labels = parsed.labels.isEmpty ? [""] : parsed.labels
        let statusString = it["status"] as? String
        let read = statusString == "read"
        let reading = statusString == "reading"

        var out: [String: Any] = [:]
        out["id"] = it["id"] ?? NSNull()
        out["series"] = oldSeries.isEmpty ? oldTitle : oldSeries
        out["title"] = oldSeries.isEmpty ? "" : oldTitle
        out["issues"] = labels.map { ["label": $0, "done": read, "url": ""] as [String: Any] }
        out["started"] = reading
        out["writer"] = it["writer"] ?? NSNull()
        out["artist"] = it["artist"] ?? NSNull()
        out["publisher"] = it["publisher"] ?? NSNull()
        out["year"] = it["year"] ?? NSNull()
        out["cover"] = it["cover"] ?? NSNull()
        out["tags"] = it["tags"] ?? NSNull()
        out["notes"] = it["notes"] ?? NSNull()
        out["rating"] = it["rating"] ?? NSNull()
        out["addedAt"] = it["addedAt"] ?? NSNull()
        return out
    }

    /// `String(spec == null ? '' : spec)`: JS's loose string coercion of whatever
    /// the old `issue` field held.
    private static func issueSpecString(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let i as Int: return String(i)
        case let d as Double:
            return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    private static func isOne(_ value: Any?) -> Bool {
        switch value {
        case let i as Int: return i == 1
        case let d as Double: return d == 1
        case let n as NSNumber: return n.intValue == 1 && n.doubleValue == 1
        default: return false
        }
    }
}
