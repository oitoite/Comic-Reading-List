import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Metadata models
//
// Port of the comic metadata API section (assets/app.js lines 485-686). There is no
// series-search endpoint, so the app searches issues and folds them into the series
// they belong to (`MetadataAPI.searchSeries`), then pages through one series's issues
// (`seriesIssues`) and fills in per-issue detail (cover/credits) lazily (`issueDetail`).

/// A series folded out of an issue search: `seriesId`/`seriesName` repeated once per
/// hit, counted here as `hits`.
public struct MetaSeries: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Raw series title, e.g. "Fantastic Four (1998 - 2012)".
    public var title: String
    /// `title` with the trailing run-years parenthetical stripped.
    public var name: String
    public var hits: Int

    public init(id: Int, title: String, name: String, hits: Int) {
        self.id = id
        self.title = title
        self.name = name
        self.hits = hits
    }
}

public struct MetaIssue: Hashable, Sendable {
    public var id: Int?
    public var issueNumber: String
    public var title: String
    public var detailUrl: String
    /// Non-empty when this issue is on Marvel Unlimited.
    public var unlimitedDate: String?
    public var yearPage: Int?

    public init(id: Int? = nil, issueNumber: String = "", title: String = "",
                detailUrl: String = "", unlimitedDate: String? = nil, yearPage: Int? = nil) {
        self.id = id
        self.issueNumber = issueNumber
        self.title = title
        self.detailUrl = detailUrl
        self.unlimitedDate = unlimitedDate
        self.yearPage = yearPage
    }

    /// Lenient parse from an API item: numbers may arrive as Int, Double or String.
    public init(fromRaw raw: [String: Any]) {
        self.id = MetadataHelpers.parseIntLoose(raw["id"])
        self.issueNumber = MetadataHelpers.parseStringLoose(raw["issueNumber"])
        self.title = MetadataHelpers.parseStringLoose(raw["title"])
        self.detailUrl = Sanitizer.safeURL(raw["detailUrl"])
        let unlimited = MetadataHelpers.parseStringLoose(raw["unlimitedDate"])
        self.unlimitedDate = unlimited.isEmpty ? nil : unlimited
        self.yearPage = MetadataHelpers.parseIntLoose(raw["yearPage"])
    }
}

public struct MetaIssueDetail: Hashable, Sendable {
    public var cover: String
    public var description: String
    public var pageCount: Int
    public var writer: String
    public var artist: String

    public init(cover: String = "", description: String = "", pageCount: Int = 0,
                writer: String = "", artist: String = "") {
        self.cover = cover
        self.description = description
        self.pageCount = pageCount
        self.writer = writer
        self.artist = artist
    }
}

public struct MetaSearchResult: Sendable {
    public var series: [MetaSeries]
    /// True when the search hit the API's own result cap (more series may exist).
    public var capped: Bool

    public init(series: [MetaSeries], capped: Bool) {
        self.series = series
        self.capped = capped
    }
}

public struct MetaIssuesResult: Sendable {
    public var items: [MetaIssue]
    public var total: Int
    public var seriesName: String

    public init(items: [MetaIssue], total: Int, seriesName: String) {
        self.items = items
        self.total = total
        self.seriesName = seriesName
    }
}

public struct MetadataError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// MARK: - Pure helpers

public enum MetadataHelpers {

    /// `metaQuery`: the search backend 500s on `( ) * : % ?` and apostrophes and treats
    /// the query as AND-ed tokens, so punctuation becomes a space rather than being
    /// deleted — "Kraven's Last Hunt" has to stay four tokens to match.
    public static func query(_ text: String?) -> String {
        let input = text ?? ""
        var firstPass = ""
        firstPass.reserveCapacity(input.count)
        for scalar in input.unicodeScalars {
            firstPass.unicodeScalars.append(isQueryAllowed(scalar) ? scalar : " ")
        }
        // Underscores are `\w`, so the pass above kept them, but a second explicit
        // replace turns them into spaces too, matching the JS `.replace(/_/g, ' ')`.
        let underscoresReplaced = firstPass.replacingOccurrences(of: "_", with: " ")
        let collapsed = underscoresReplaced.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(100))
    }

    /// Matches JS `/[^\w\s&"À-ɏ-]/` — `\w` (word chars, i.e. alphanumerics + `_`),
    /// whitespace, `&`, `"`, the Latin-1 Supplement/Extended-A letter range À-ɏ, and `-`.
    private static func isQueryAllowed(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "_" { return true }
        if CharacterSet.alphanumerics.contains(scalar) { return true }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        if scalar == "&" || scalar == "\"" || scalar == "-" { return true }
        if scalar.value >= 0x00C0 && scalar.value <= 0x024F { return true } // À-ɏ
        return false
    }

    /// `seriesName`: Marvel titles carry their run years — "Fantastic Four (1998 - 2012)"
    /// — strip that trailing parenthetical.
    public static func seriesName(_ title: String?) -> String {
        let input = title ?? ""
        let pattern = #"\s*\((\d{4})(\s*[-–]\s*(\d{4}|Present))?\)\s*$"#
        let stripped = input.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        return Sanitizer.str(stripped, Limits.nameLength)
    }

    /// The API returns newest first, and issue numbers are strings that may be decimal
    /// ("605.1", "0.5"), so sort on the parsed number and keep unparseable ones last.
    public static func sortIssuesAscending(_ items: [MetaIssue]) -> [MetaIssue] {
        items.enumerated().sorted { lhs, rhs in
            let x = Double(lhs.element.issueNumber)
            let y = Double(rhs.element.issueNumber)
            switch (x, y) {
            case (nil, nil): return lhs.offset < rhs.offset // stable: keep original order
            case (nil, _): return false
            case (_, nil): return true
            case let (xv?, yv?):
                if xv == yv { return lhs.offset < rhs.offset }
                return xv < yv
            }
        }.map { $0.element }
    }

    /// Some series give every issue the same number — five one-shots all called #1.
    /// Labels have to stay distinct or the range box and the per-issue links collide.
    public static func uniqueLabels(_ labels: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return labels.map { raw in
            let base = raw.isEmpty ? "Issue" : raw
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            return count == 1 ? base : Sanitizer.str("\(base) (\(count))", 40)
        }
    }

    public static func yearFromSeriesTitle(_ title: String?) -> Int? {
        let input = title ?? ""
        guard let range = input.range(of: #"\((\d{4})"#, options: .regularExpression) else { return nil }
        let match = String(input[range]) // "(1998"
        let digits = match.dropFirst() // "1998"
        return Sanitizer.year(String(digits))
    }

    /// Marvel serves its artwork over http; the site is https, so upgrade or the
    /// browser blocks it as mixed content.
    public static func httpsURL(_ value: String?) -> String {
        let input = value ?? ""
        let upgraded = input.replacingOccurrences(of: "^http://", with: "https://", options: [.regularExpression, .caseInsensitive])
        return Sanitizer.safeURL(upgraded)
    }

    /// The list endpoints omit covers and creators; the per-issue endpoint has both.
    public static func marvelCoverURL(path: String?, extension ext: String?, variant: String? = nil) -> String {
        guard let path = path, !path.isEmpty else { return "" }
        if path.range(of: "image_not_available", options: .caseInsensitive) != nil { return "" }
        let v = (variant?.isEmpty ?? true) ? "portrait_uncanny" : variant!
        let e = (ext?.isEmpty ?? true) ? "jpg" : ext!
        return httpsURL(path + "/" + v + "." + e)
    }

    public static func credits(from creators: [Any]?) -> (writer: String, artist: String) {
        var writer = ""
        var artist = ""
        for case let c as [String: Any] in (creators ?? []) {
            guard let name = c["name"] as? String, !name.isEmpty else { continue }
            let role = (c["role"] as? String ?? "").lowercased()
            if writer.isEmpty && role.contains("writer") {
                writer = Sanitizer.str(name, Limits.nameLength)
            }
            if artist.isEmpty && (role.contains("penciler") || role.contains("penciller") || role.contains("artist")) {
                artist = Sanitizer.str(name, Limits.nameLength)
            }
        }
        return (writer, artist)
    }

    public static func entryFromMeta(series: MetaSeries, items: [MetaIssue], onlyUnlimited: Bool) -> Entry {
        let chosen = Array(
            sortIssuesAscending(items)
                .filter { onlyUnlimited ? ($0.unlimitedDate?.isEmpty == false) : true }
                .prefix(Limits.maxIssues)
        )

        let labels = uniqueLabels(chosen.map { Sanitizer.str($0.issueNumber, 40) })

        var year = yearFromSeriesTitle(series.title)
        if year == nil {
            for it in chosen {
                if let y = it.yearPage, (1900...2200).contains(y) {
                    if year == nil || y < year! { year = y }
                }
            }
        }

        let issues = chosen.enumerated().map { idx, it in
            Issue(label: labels[idx], done: false, url: Sanitizer.safeURL(it.detailUrl))
        }

        return Entry(
            series: series.name.isEmpty ? seriesName(series.title) : series.name,
            title: "",
            issues: issues,
            started: false,
            writer: "",
            artist: "",
            publisher: "Marvel",
            year: year,
            service: Service.marvelUnlimitedID,
            url: "",
            cover: "",
            tags: [],
            notes: "",
            rating: 0
        )
    }

    /// Extracts the numeric issue id out of a Marvel detail-page URL like
    /// `https://www.marvel.com/comics/issue/12345/...`.
    public static func marvelIssueID(from url: String) -> String? {
        guard let range = url.range(of: #"/comics/issue/(\d+)"#, options: .regularExpression) else { return nil }
        let matched = String(url[range])
        guard let digitsRange = matched.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return String(matched[digitsRange])
    }

    /// `metaError`.
    public static func errorMessage(body: Any?, status: Int) -> String {
        if let dict = body as? [String: Any] {
            if let detail = dict["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let detailArray = dict["detail"] as? [Any] {
                let msgs = detailArray.compactMap { ($0 as? [String: Any])?["msg"] as? String }.filter { !$0.isEmpty }
                if !msgs.isEmpty { return msgs.joined(separator: "; ") }
            }
        }
        if status == 429 {
            return "Too many requests — the API allows 60 a minute. Wait a moment and try again."
        }
        if status >= 500 {
            return "The metadata API had an error on that query. Try different wording."
        }
        return "The metadata API returned HTTP \(status)."
    }

    // MARK: loose numeric/string parsing (API fields may arrive as Int/Double/String)

    public static func parseIntLoose(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let d as Double: return d.isFinite ? Int(d) : nil
        case let s as String:
            if let i = Int(s) { return i }
            if let d = Double(s), d.isFinite { return Int(d) }
            return nil
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    public static func parseStringLoose(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let i as Int: return String(i)
        case let d as Double: return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }
}

// MARK: - MetadataAPI

public actor MetadataAPI {

    public static let defaultBase = URL(string: "https://marvel.emreparker.com")!

    private static let searchLimit = 200
    private static let seriesPage = 500
    private static let maxPages = 5

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = (baseURL ?? MetadataAPI.defaultBase)
        self.session = session
    }

    public func searchSeries(_ query: String) async throws -> MetaSearchResult {
        let q = MetadataHelpers.query(query)
        guard q.count >= 2 else {
            throw MetadataError("Type at least two letters.")
        }
        let body = try await fetch(path: "/v1/search/issues", params: ["q": q, "limit": String(Self.searchLimit)])
        return Self.parseSearch(body)
    }

    public func seriesIssues(_ seriesID: Int, onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> MetaIssuesResult {
        var all: [MetaIssue] = []
        var offset = 0
        var pageNo = 1
        var total = 0
        var name = ""

        while true {
            let body = try await fetch(
                path: "/v1/series/\(seriesID)/issues",
                params: ["limit": String(Self.seriesPage), "offset": String(offset)]
            )
            let page = Self.parseIssuesPage(body)
            all.append(contentsOf: page.items)
            total = page.total ?? all.count
            name = page.seriesName
            onProgress?(all.count, total)

            let more = page.hasNext && !page.items.isEmpty && pageNo < Self.maxPages && all.count < Limits.maxIssues
            if !more { break }
            offset += page.items.count
            pageNo += 1
        }
        return MetaIssuesResult(items: all, total: total, seriesName: name)
    }

    public func issueDetail(_ issueID: Int) async throws -> MetaIssueDetail {
        do {
            let body = try await fetch(path: "/v1/issues/\(issueID)", params: [:])
            return Self.parseIssueDetail(body)
        } catch {
            // A missing cover/detail is not a failure, matching the JS `.catch`.
            return MetaIssueDetail()
        }
    }

    // MARK: networking

    private func fetch(path: String, params: [String: String]) async throws -> Any {
        guard var components = URLComponents(string: baseURL.absoluteString + path) else {
            throw MetadataError("Could not build a request URL.")
        }
        let items = params.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            throw MetadataError("Could not build a request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MetadataError("The metadata API could not be reached.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        // An HTML error page or empty body fails to parse as JSON; that is not itself
        // fatal — `metaError` still needs a chance to read the HTTP status.
        let parsedBody = JSON.parse(data)

        guard (200...299).contains(status) else {
            throw MetadataError(MetadataHelpers.errorMessage(body: parsedBody, status: status))
        }
        // `typeof body !== 'object'` in the JS also accepts arrays; downstream parsing
        // treats anything that is not a dictionary as an empty one.
        guard let body = parsedBody, body is [String: Any] || body is [Any] else {
            throw MetadataError("The metadata API sent something unreadable.")
        }
        return body
    }

    // MARK: pure JSON parsing (unit-testable without network)

    static func parseSearch(_ body: Any) -> MetaSearchResult {
        let dict = body as? [String: Any] ?? [:]
        let items = (dict["items"] as? [Any]) ?? []

        var order: [Int] = []
        var byID: [Int: MetaSeries] = [:]

        for case let it as [String: Any] in items {
            guard let seriesID = MetadataHelpers.parseIntLoose(it["seriesId"]) else { continue }
            if var existing = byID[seriesID] {
                existing.hits += 1
                byID[seriesID] = existing
            } else {
                let rawTitle = MetadataHelpers.parseStringLoose(it["seriesName"])
                byID[seriesID] = MetaSeries(
                    id: seriesID,
                    title: Sanitizer.str(rawTitle, 200),
                    name: MetadataHelpers.seriesName(rawTitle),
                    hits: 1
                )
                order.append(seriesID)
            }
        }

        return MetaSearchResult(
            series: order.compactMap { byID[$0] },
            capped: items.count >= searchLimit
        )
    }

    struct IssuesPage {
        var items: [MetaIssue]
        var total: Int?
        var seriesName: String
        var hasNext: Bool
    }

    static func parseIssuesPage(_ body: Any) -> IssuesPage {
        let dict = body as? [String: Any] ?? [:]
        let rawItems = (dict["items"] as? [Any]) ?? []
        let items: [MetaIssue] = rawItems.compactMap { item in
            guard let raw = item as? [String: Any] else { return nil }
            return MetaIssue(fromRaw: raw)
        }
        let total = MetadataHelpers.parseIntLoose(dict["total"])
        let name = Sanitizer.str(MetadataHelpers.parseStringLoose(dict["series_name"]), 200)
        let hasNext = Sanitizer.bool(dict["has_next"])
        return IssuesPage(items: items, total: total, seriesName: name, hasNext: hasNext)
    }

    static func parseIssueDetail(_ body: Any) -> MetaIssueDetail {
        let dict = body as? [String: Any] ?? [:]
        let creators = dict["creators"] as? [Any]
        let credits = MetadataHelpers.credits(from: creators)
        let coverDict = dict["cover"] as? [String: Any]
        let cover = MetadataHelpers.marvelCoverURL(
            path: coverDict?["path"] as? String,
            extension: coverDict?["extension"] as? String
        )
        return MetaIssueDetail(
            cover: cover,
            description: Sanitizer.str(dict["description"], 1200),
            pageCount: MetadataHelpers.parseIntLoose(dict["pageCount"]) ?? 0,
            writer: credits.writer,
            artist: credits.artist
        )
    }
}
