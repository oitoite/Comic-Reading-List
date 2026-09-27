import Foundation

// MARK: - ShareCodec
//
// Port of the web app's share-link section (assets/app.js lines 685-811). A playlist
// is packed into short keys, JSON-encoded, gzipped, and base64url-encoded straight into
// the URL hash — no server involved. Everything decoded from someone else's link is
// treated as hostile and run back through `Sanitizer`.

public enum ShareError: Error, Equatable {
    case invalidBase64
    case invalidJSON
    case unsupportedEncoding
}

public enum ShareCodec {

    public static let webAppURL = URL(string: "https://oitoite.github.io/Comic-Reading-List/")!

    // MARK: base64url

    public static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64urlDecode(_ s: String) throws -> Data {
        var t = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        guard let data = Data(base64Encoded: t) else { throw ShareError.invalidBase64 }
        return data
    }

    // MARK: pack / unpack

    /// Port of `packList` (app.js 705-736): short keys, optional fields only when
    /// non-empty/non-zero, entries capped at `Limits.maxShareEntries`.
    public static func pack(_ list: Playlist, includeProgress: Bool) -> [String: Any] {
        var e: [[String: Any]] = []
        for en in list.entries.prefix(Limits.maxShareEntries) {
            var o: [String: Any] = [:]
            o["s"] = en.series
            if !en.title.isEmpty { o["t"] = en.title }
            o["i"] = en.issues.map { $0.label }

            var iu: [String: Any] = [:]
            for (idx, issue) in en.issues.enumerated() where !issue.url.isEmpty {
                iu[String(idx)] = issue.url
            }
            if !iu.isEmpty { o["iu"] = iu }

            if includeProgress {
                var done: [Int] = []
                for (idx, issue) in en.issues.enumerated() where issue.done {
                    done.append(idx)
                }
                if !done.isEmpty { o["d"] = done }
                if en.started { o["st"] = 1 }
            }

            if !en.writer.isEmpty { o["w"] = en.writer }
            if !en.artist.isEmpty { o["a"] = en.artist }
            if !en.publisher.isEmpty { o["p"] = en.publisher }
            if let year = en.year, year != 0 { o["y"] = year }
            if !en.service.isEmpty { o["sv"] = en.service }
            if !en.url.isEmpty { o["u"] = en.url }
            if !en.cover.isEmpty { o["c"] = en.cover }
            if !en.tags.isEmpty { o["g"] = en.tags }
            if !en.notes.isEmpty { o["o"] = en.notes }
            if en.rating != 0 { o["r"] = en.rating }
            e.append(o)
        }

        return [
            "v": 2,
            "n": list.name,
            "s": list.service,
            "e": e
        ]
    }

    /// Port of `unpackList` (app.js 740-766): everything here is hostile input, run
    /// through the same sanitizers as any file import.
    public static func unpack(_ obj: Any?) -> Playlist? {
        guard let dict = obj as? [String: Any] else { return nil }
        let entriesRaw = (dict["e"] as? [Any]) ?? []
        let entries: [Entry] = entriesRaw.prefix(Limits.maxShareEntries).compactMap { item in
            guard let o = item as? [String: Any] else { return nil }

            let doneSet = doneIndices(o["d"])
            let urls = urlMap(o["iu"])
            let labels = (o["i"] as? [Any]) ?? []

            let issues: [[String: Any]] = labels.prefix(Limits.maxIssues).enumerated().map { idx, label in
                let labelString = Sanitizer.str(jsString(label), Limits.labelLength)
                let url = Sanitizer.safeURL(urls[idx])
                return [
                    "label": labelString,
                    "done": doneSet.contains(idx),
                    "url": url
                ]
            }

            var entryDict: [String: Any] = [
                "issues": issues,
                "started": Sanitizer.bool(o["st"])
            ]
            let passthrough: [String: String] = [
                "s": "series", "t": "title", "w": "writer", "a": "artist",
                "p": "publisher", "y": "year", "sv": "service", "u": "url",
                "c": "cover", "g": "tags", "o": "notes", "r": "rating"
            ]
            for (shortKey, longKey) in passthrough {
                if let value = o[shortKey] { entryDict[longKey] = value }
            }
            return Sanitizer.entry(entryDict)
        }

        return Playlist(
            id: IDs.make(),
            name: {
                let name = Sanitizer.str(jsString(dict["n"]), Limits.listNameLength)
                return name.isEmpty ? "Shared list" : name
            }(),
            service: Sanitizer.serviceID(jsString(dict["s"]), fallback: "mu"),
            createdAt: Timestamps.now(),
            entries: entries
        )
    }

    /// `o.d`: array of issue indices marked done. Non-integer entries are ignored,
    /// matching the JS `indexOf` comparison, which never matches a non-integer index.
    private static func doneIndices(_ raw: Any?) -> Set<Int> {
        guard let array = raw as? [Any] else { return [] }
        return Set(array.compactMap { asWholeInt($0) })
    }

    /// `o.iu`: an object keyed by issue index, as either a JSON string key ("0") or,
    /// when built programmatically rather than decoded from JSON, a numeric key.
    private static func urlMap(_ raw: Any?) -> [Int: Any] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [Int: Any] = [:]
        for (key, value) in dict {
            if let idx = Int(key) {
                out[idx] = value
            }
        }
        return out
    }

    private static func asWholeInt(_ value: Any) -> Int? {
        // `NSNumber(value: 0/1) as? Bool` can succeed (NSNumber boxes small integers and
        // booleans the same way), so a real boolean is only excluded by checking the
        // exact dynamic type via Mirror rather than a plain `as? Bool` cast — otherwise
        // a done-index of 0 would be misread as `false` and silently dropped.
        if type(of: value) == Bool.self { return nil }
        switch value {
        case let i as Int:
            return i
        case let d as Double:
            return d.truncatingRemainder(dividingBy: 1) == 0 ? Int(d) : nil
        case let n as NSNumber:
            let d = n.doubleValue
            return d.truncatingRemainder(dividingBy: 1) == 0 ? Int(d) : nil
        default:
            return nil
        }
    }

    /// Mirrors JS's `String(v)` coercion used on the top-level `n`/`s` fields before
    /// sanitizing, so a numeric or boolean value still produces a comparable string
    /// instead of being dropped the way a non-string entry field is.
    private static func jsString(_ value: Any?) -> String {
        switch value {
        case let s as String:
            return s
        case let i as Int:
            return String(i)
        case let b as Bool:
            return b ? "true" : "false"
        case let d as Double:
            if d.truncatingRemainder(dividingBy: 1) == 0 && abs(d) < 1e15 {
                return String(Int(d))
            }
            return String(d)
        case let n as NSNumber:
            return n.stringValue
        default:
            return ""
        }
    }

    // MARK: encode / decode

    /// JSON (compact, sorted keys) -> gzip -> "g" + base64url; if gzip fails,
    /// "r" + base64url of the raw JSON — matching `encodeShare`'s CompressionStream
    /// fallback for browsers without gzip support.
    public static func encode(_ obj: [String: Any]) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        if let gzipped = try? Gzip.compress(json) {
            return "g" + base64urlEncode(gzipped)
        }
        return "r" + base64urlEncode(json)
    }

    /// Port of `decodeShare`: "g" -> gunzip, "r" -> raw, anything else -> the whole
    /// string is treated as raw base64url (matching the JS fallback path).
    public static func decode(_ code: String) throws -> Any {
        let kind = code.first
        let body: Substring
        let bytes: Data
        switch kind {
        case "g", "r":
            body = code.dropFirst()
            bytes = try base64urlDecode(String(body))
        default:
            bytes = try base64urlDecode(code)
        }

        let jsonData: Data
        if kind == "g" {
            jsonData = try Gzip.decompress(bytes)
        } else {
            jsonData = bytes
        }

        guard let parsed = JSON.parse(jsonData) else { throw ShareError.invalidJSON }
        return parsed
    }

    // MARK: URLs

    public static func shareURL(for list: Playlist, includeProgress: Bool, base: URL = webAppURL) throws -> URL {
        let code = try encode(pack(list, includeProgress: includeProgress))
        var s = base.absoluteString
        if let hashRange = s.range(of: "#") {
            s.removeSubrange(hashRange.lowerBound..<s.endIndex)
        }
        guard let url = URL(string: s + "#list=" + code) else { throw ShareError.invalidJSON }
        return url
    }

    /// Accepts `#list=CODE` fragments, `list=CODE` query items, and the host or path
    /// of a custom-scheme URL like `unlimitedreadinglist://list/CODE` or
    /// `unlimitedreadinglist://?list=CODE`.
    public static func extractCode(from url: URL) -> String? {
        if let fragment = url.fragment, !fragment.isEmpty {
            if let code = queryItem(named: "list", in: fragment) {
                return code
            }
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let items = components.queryItems,
               let code = items.first(where: { $0.name == "list" })?.value,
               !code.isEmpty {
                return code
            }
            // unlimitedreadinglist://list/CODE — "list" is the host, CODE is the path.
            if components.host == "list" {
                let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !path.isEmpty { return path }
            }
            // unlimitedreadinglist:///list/CODE (no host, "list" leads the path).
            let pathParts = components.path.split(separator: "/").map(String.init)
            if pathParts.count >= 2, pathParts[0] == "list" {
                return pathParts[1]
            }
        }
        return nil
    }

    /// Parses `a=b&c=d`-shaped text (a URL fragment or query string) for a given key.
    private static func queryItem(named name: String, in raw: String) -> String? {
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            if parts[0] == Substring(name) {
                let value = String(parts[1])
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
