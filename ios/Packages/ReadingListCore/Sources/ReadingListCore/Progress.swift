import Foundation

// MARK: - Derived status & progress
//
// Exact port of the web app's `doneCount` / `statusOf` / `listProgress` / `nextIssue`
// (assets/app.js lines 414-482). Progress is counted in issues, not entries: a
// 30-issue run is not one tick.

public extension Entry {
    var doneCount: Int {
        issues.filter { $0.done }.count
    }

    var status: ReadStatus {
        let done = doneCount
        if done == issues.count { return .finished }
        if done > 0 || started { return .reading }
        return .unread
    }

    var progressFraction: Double {
        guard !issues.isEmpty else { return 0 }
        return Double(doneCount) / Double(issues.count)
    }

    /// The first not-done issue, else the last issue.
    var nextIssue: Issue? {
        for issue in issues where !issue.done { return issue }
        return issues.last
    }
}

public struct ListProgress {
    public var done: Int
    public var total: Int
    /// Rounded percentage; 0 when `total` is 0.
    public var percent: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
        self.percent = total > 0 ? Int((Double(done) / Double(total) * 100).rounded()) : 0
    }
}

public extension Playlist {
    var progress: ListProgress {
        var total = 0
        var done = 0
        for entry in entries {
            total += entry.issues.count
            done += entry.doneCount
        }
        return ListProgress(done: done, total: total)
    }
}
