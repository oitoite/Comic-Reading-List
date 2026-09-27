import Foundation

// MARK: - Bulk paste parsing
//
// Exact port of the web app's `parseBulkLines` (assets/app.js lines 148-189).
// One entry per line: "Series #294-296 | Arc title". Blank lines and lines starting
// with `//` are ignored. A line with no `#` is one unnumbered book.

public enum BulkParser {

    public struct Result {
        public var entries: [Entry]
        public var issueCount: Int
        public var skipped: Int
        public var truncated: Bool

        public init(entries: [Entry], issueCount: Int, skipped: Int, truncated: Bool) {
            self.entries = entries
            self.issueCount = issueCount
            self.skipped = skipped
            self.truncated = truncated
        }
    }

    public static func parse(_ text: String) -> Result {
        var entries: [Entry] = []
        var skipped = 0
        var truncated = false

        // `String(text).split(/\r?\n/)`: only a bare "\n" or a "\r\n" pair separates
        // lines; a lone "\r" is left in place.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        for line in lines {
            if entries.count >= Limits.maxBulkLines {
                truncated = true
                break
            }

            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty || raw.hasPrefix("//") { continue }

            var title = ""
            var left = raw
            if let barRange = raw.range(of: "|") {
                left = String(raw[raw.startIndex..<barRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                title = String(raw[barRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var series = left
            var spec = ""
            if let hashRange = left.range(of: "#", options: .backwards) {
                series = String(left[left.startIndex..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                spec = String(left[hashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if series.isEmpty {
                skipped += 1
                continue
            }

            let parsed = spec.isEmpty ? IssueSpec.ParseResult(labels: [], truncated: false) : IssueSpec.parse(spec)
            let labels = parsed.labels.isEmpty ? [""] : parsed.labels
            if parsed.truncated { truncated = true }

            let issues = labels.map { Issue(label: $0, done: false, url: "") }
            entries.append(Entry(series: Sanitizer.str(series, 200), title: Sanitizer.str(title, 200), issues: issues))
        }

        let issueCount = entries.reduce(0) { $0 + $1.issues.count }
        return Result(entries: entries, issueCount: issueCount, skipped: skipped, truncated: truncated)
    }
}
