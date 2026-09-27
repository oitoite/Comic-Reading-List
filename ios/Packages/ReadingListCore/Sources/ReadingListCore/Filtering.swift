import Foundation

// MARK: - Filtering & sorting
//
// Exact port of the web app's `visibleEntries` (assets/app.js lines 907-933).
// Sorting is stable, mirroring the ECMA2019+ guarantee that `Array.prototype.sort`
// relies on (ties keep their original relative order).

public struct EntryFilter {
    public var query: String
    public var status: ReadStatus?

    public init(query: String = "", status: ReadStatus? = nil) {
        self.query = query
        self.status = status
    }
}

public enum EntryFiltering {

    public static func visible(_ entries: [Entry], filter: EntryFilter, sort: SortOrder) -> [Entry] {
        var result = entries

        if let status = filter.status {
            result = result.filter { $0.status == status }
        }

        let q = filter.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { entry in
                let haystack = [
                    entry.series, entry.title, entry.writer, entry.artist, entry.publisher, entry.notes,
                    entry.tags.joined(separator: " "),
                    entry.issues.map { $0.label }.joined(separator: " ")
                ].joined(separator: " ")
                return haystack.lowercased().contains(q)
            }
        }

        guard let comparator = comparator(for: sort) else { return result }

        return result.enumerated()
            .sorted { lhs, rhs in
                let c = comparator(lhs.element, rhs.element)
                if c != 0 { return c < 0 }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// `nil` for `.order`: entries keep whatever order they arrived in.
    private static func comparator(for sort: SortOrder) -> ((Entry, Entry) -> Int)? {
        switch sort {
        case .order:
            return nil
        case .added:
            return { a, b in sign(b.addedAt - a.addedAt) }
        case .series:
            return { a, b in
                let c = compareLocalized(a.series, b.series)
                return c != 0 ? c : compareLocalized(a.title, b.title)
            }
        case .title:
            return { a, b in
                compareLocalized(a.title.isEmpty ? a.series : a.title, b.title.isEmpty ? b.series : b.title)
            }
        case .rating:
            return { a, b in
                let diff = b.rating - a.rating
                return diff != 0 ? sign(Double(diff)) : compareLocalized(a.series, b.series)
            }
        case .year:
            return { a, b in
                sign(Double((b.year ?? 0) - (a.year ?? 0)))
            }
        case .progress:
            return { a, b in
                sign(b.progressFraction - a.progressFraction)
            }
        }
    }

    private static func sign(_ d: Double) -> Int {
        d == 0 ? 0 : (d < 0 ? -1 : 1)
    }

    /// Mirrors JavaScript's default (locale-aware, case-insensitive) `localeCompare`.
    private static func compareLocalized(_ a: String, _ b: String) -> Int {
        switch a.localizedStandardCompare(b) {
        case .orderedAscending: return -1
        case .orderedSame: return 0
        case .orderedDescending: return 1
        }
    }
}
