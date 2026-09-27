import Foundation

// MARK: - Issue spec parsing
//
// Exact port of the web app's `parseIssueSpec` / `summarizeIssues` / `mergeIssues`
// (assets/app.js lines 66-108, 111-145, 1355-1365). "294-296, 300, Annual 1" expands
// to five labels; anything that is not a plain numeric range is kept verbatim, so
// "1.MU" or "Director's Cut" survive untouched.

public enum IssueSpec {

    public struct ParseResult {
        public var labels: [String]
        public var truncated: Bool

        public init(labels: [String], truncated: Bool) {
            self.labels = labels
            self.truncated = truncated
        }
    }

    /// `^(.*?)(\d+)\s*(?:-|–|—|\.{2,}|\bto\b)\s*(.*?)(\d+)$`, case-insensitive.
    private static let rangeRegex: NSRegularExpression = {
        let pattern = "^(.*?)(\\d+)\\s*(?:-|\u{2013}|\u{2014}|\\.{2,}|\\bto\\b)\\s*(.*?)(\\d+)$"
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private struct RangeMatch {
        var prefix: String
        var leftNum: String
        var rightPrefix: String
        var rightNum: String
    }

    private static func matchRange(_ tok: String) -> RangeMatch? {
        let ns = tok as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = rangeRegex.firstMatch(in: tok, options: [], range: full), m.numberOfRanges == 5 else {
            return nil
        }
        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            guard r.location != NSNotFound else { return "" }
            return ns.substring(with: r)
        }
        return RangeMatch(prefix: group(1), leftNum: group(2), rightPrefix: group(3), rightNum: group(4))
    }

    /// Strips one leading run of `#` characters plus any whitespace that follows it,
    /// mirroring `.replace(/^#+\s*/, '')`.
    private static func stripLeadingHash(_ s: String) -> String {
        var chars = Substring(s)
        var strippedAny = false
        while let first = chars.first, first == "#" {
            chars.removeFirst()
            strippedAny = true
        }
        if strippedAny {
            while let first = chars.first, first.isWhitespace {
                chars.removeFirst()
            }
        }
        return String(chars)
    }

    private static func isZeroPadded(_ digits: String) -> Bool {
        digits.count >= 2 && digits.first == "0"
    }

    private static func separator(after prefix: String) -> String {
        guard let last = prefix.last else { return "" }
        if last.isWhitespace || last == "#" || last == "." { return "" }
        return " "
    }

    private static func zeroPadded(_ n: Int, width: Int) -> String {
        var s = String(n)
        while s.count < width { s = "0" + s }
        return s
    }

    public static func parse(_ spec: String, cap: Int = Limits.maxIssues) -> ParseResult {
        var labels: [String] = []
        var truncated = false

        let chunks = spec.components(separatedBy: CharacterSet(charactersIn: ",;\n"))

        chunkLoop: for chunk in chunks {
            if truncated { break chunkLoop }

            var tok = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            tok = stripLeadingHash(tok)
            tok = tok.trimmingCharacters(in: .whitespacesAndNewlines)
            if tok.isEmpty { continue }

            if let m = matchRange(tok), let from = Int(m.leftNum), let to = Int(m.rightNum) {
                let prefix = m.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                var rightPrefix = stripLeadingHash(m.rightPrefix.trimmingCharacters(in: .whitespacesAndNewlines))
                rightPrefix = rightPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                let sameSide = rightPrefix.isEmpty || rightPrefix.lowercased() == prefix.lowercased()

                if sameSide && to >= from {
                    let pad = isZeroPadded(m.leftNum) ? m.leftNum.count : 0
                    let sep = separator(after: prefix)
                    var n = from
                    while n <= to {
                        if labels.count >= cap {
                            truncated = true
                            break chunkLoop
                        }
                        let numStr = zeroPadded(n, width: pad)
                        labels.append(Sanitizer.str(prefix + sep + numStr, Limits.labelLength))
                        n += 1
                    }
                    continue
                }
            }

            if labels.count >= cap {
                truncated = true
                break chunkLoop
            }
            labels.append(Sanitizer.str(tok, Limits.labelLength))
        }

        return ParseResult(labels: labels, truncated: truncated)
    }

    /// The inverse, close enough to round-trip: consecutive numbers with the same
    /// prefix and zero-padding collapse back into a range so the edit field stays
    /// readable.
    public static func summarize(_ issues: [Issue]) -> String {
        var parts: [String] = []
        var runPrefix: String?
        var runFrom: Int?
        var runTo: Int?
        var runPad = 0

        func flush() {
            guard let from = runFrom, let to = runTo, let prefix = runPrefix else { return }
            let a = zeroPadded(from, width: runPad)
            let b = zeroPadded(to, width: runPad)
            let sep = separator(after: prefix)
            parts.append(from == to ? prefix + sep + a : prefix + sep + a + "-" + b)
            runPrefix = nil
            runFrom = nil
            runTo = nil
            runPad = 0
        }

        for issue in issues {
            let label = issue.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, let trail = trailingNumber(label) else {
                flush()
                if !label.isEmpty { parts.append(label) }
                continue
            }
            var prefix = trail.prefix
            while let last = prefix.last, last.isWhitespace { prefix.removeLast() }
            guard let n = Int(trail.numStr) else {
                flush()
                parts.append(label)
                continue
            }
            let width = isZeroPadded(trail.numStr) ? trail.numStr.count : 0

            if let curTo = runTo, prefix == runPrefix, width == runPad, n == curTo + 1 {
                runTo = n
                continue
            }
            flush()
            runPrefix = prefix
            runFrom = n
            runTo = n
            runPad = width
        }
        flush()
        return parts.joined(separator: ", ")
    }

    /// `^(.*?)(\d+)$`: the maximal trailing run of ASCII digits, plus everything
    /// before it.
    private static func trailingNumber(_ label: String) -> (prefix: String, numStr: String)? {
        var numChars: [Character] = []
        var idx = label.endIndex
        while idx > label.startIndex {
            let prev = label.index(before: idx)
            let c = label[prev]
            if c.isASCII && c.isNumber {
                numChars.append(c)
                idx = prev
            } else {
                break
            }
        }
        guard !numChars.isEmpty else { return nil }
        return (String(label[label.startIndex..<idx]), String(numChars.reversed()))
    }

    /// For each new label, keep `done`/`url` from the first existing issue with the
    /// same label (in order), else a fresh issue.
    public static func mergeIssues(existing: [Issue], labels: [String]) -> [Issue] {
        guard !labels.isEmpty else { return [Issue()] }

        var pool: [String: [Issue]] = [:]
        for issue in existing {
            pool[issue.label, default: []].append(issue)
        }

        return labels.map { label in
            if var bucket = pool[label], !bucket.isEmpty {
                let prev = bucket.removeFirst()
                pool[label] = bucket
                return Issue(label: label, done: prev.done, url: prev.url)
            }
            return Issue(label: label, done: false, url: "")
        }
    }
}
