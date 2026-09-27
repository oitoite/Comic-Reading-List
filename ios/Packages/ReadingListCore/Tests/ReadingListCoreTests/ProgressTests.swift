import XCTest
@testable import ReadingListCore

final class ProgressTests: XCTestCase {

    func testUnreadStatus() {
        let e = Entry(series: "X", issues: [Issue(label: "1"), Issue(label: "2")])
        XCTAssertEqual(e.status, .unread)
        XCTAssertEqual(e.doneCount, 0)
    }

    func testStartedButNothingDoneIsReading() {
        var e = Entry(series: "X", issues: [Issue(label: "1"), Issue(label: "2")])
        e.started = true
        XCTAssertEqual(e.status, .reading)
    }

    func testSomeDoneIsReadingEvenWithoutStarted() {
        var e = Entry(series: "X", issues: [Issue(label: "1", done: true), Issue(label: "2")])
        XCTAssertEqual(e.status, .reading)
        e.started = false
        XCTAssertEqual(e.status, .reading)
    }

    func testAllDoneIsFinished() {
        let e = Entry(series: "X", issues: [Issue(label: "1", done: true), Issue(label: "2", done: true)])
        XCTAssertEqual(e.status, .finished)
        XCTAssertEqual(e.doneCount, 2)
        XCTAssertEqual(e.progressFraction, 1.0)
    }

    func testProgressFraction() {
        let e = Entry(series: "X", issues: [Issue(label: "1", done: true), Issue(label: "2"), Issue(label: "3"), Issue(label: "4")])
        XCTAssertEqual(e.progressFraction, 0.25, accuracy: 0.0001)
    }

    func testNextIssueIsFirstNotDone() {
        let e = Entry(series: "X", issues: [Issue(label: "1", done: true), Issue(label: "2"), Issue(label: "3")])
        XCTAssertEqual(e.nextIssue?.label, "2")
    }

    func testNextIssueFallsBackToLastWhenAllDone() {
        let e = Entry(series: "X", issues: [Issue(label: "1", done: true), Issue(label: "2", done: true)])
        XCTAssertEqual(e.nextIssue?.label, "2")
    }

    func testListProgressCountsIssuesNotEntries() {
        let e1 = Entry(series: "A", issues: (1...30).map { Issue(label: "\($0)", done: $0 <= 30) })
        let e2 = Entry(series: "B", issues: [Issue(label: "1")])
        let list = Playlist(name: "L", entries: [e1, e2])
        let p = list.progress
        XCTAssertEqual(p.total, 31)
        XCTAssertEqual(p.done, 30)
        XCTAssertEqual(p.percent, Int((30.0/31.0*100).rounded()))
    }

    func testListProgressZeroTotalGivesZeroPercent() {
        let list = Playlist(name: "L", entries: [])
        XCTAssertEqual(list.progress.percent, 0)
        XCTAssertEqual(list.progress.total, 0)
    }

    func testPercentRoundsHalfUp() {
        // 1 of 2 done isn't a half case; use 1 of 8 -> 12.5% rounds to 13.
        let e = Entry(series: "X", issues: (1...8).map { Issue(label: "\($0)", done: $0 == 1) })
        let list = Playlist(name: "L", entries: [e])
        XCTAssertEqual(list.progress.percent, 13)
    }
}
