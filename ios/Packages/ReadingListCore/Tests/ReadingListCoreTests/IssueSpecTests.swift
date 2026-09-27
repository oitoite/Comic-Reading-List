import XCTest
@testable import ReadingListCore

final class IssueSpecTests: XCTestCase {

    func testMixedListExpandsRangesAndKeepsVerbatimTokens() {
        let r = IssueSpec.parse("294-296, 300, Annual 1")
        XCTAssertEqual(r.labels, ["294", "295", "296", "300", "Annual 1"])
        XCTAssertFalse(r.truncated)
    }

    func testPrefixedRange() {
        let r = IssueSpec.parse("Annual 1-3")
        XCTAssertEqual(r.labels, ["Annual 1", "Annual 2", "Annual 3"])
    }

    func testRightSideRepeatsThePrefix() {
        let r = IssueSpec.parse("Annual 1-Annual 3")
        XCTAssertEqual(r.labels, ["Annual 1", "Annual 2", "Annual 3"])
    }

    func testWordSeparatorTo() {
        let r = IssueSpec.parse("1 to 3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testZeroPaddingIsPreserved() {
        let r = IssueSpec.parse("001-003")
        XCTAssertEqual(r.labels, ["001", "002", "003"])
    }

    func testEnDash() {
        let r = IssueSpec.parse("1\u{2013}3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testEmDash() {
        let r = IssueSpec.parse("1\u{2014}3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testDotDotSeparator() {
        let r = IssueSpec.parse("1..3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testHashPrefixedRange() {
        let r = IssueSpec.parse("#1-#3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testNonRangeDotSuffixKeptVerbatim() {
        let r = IssueSpec.parse("1.MU")
        XCTAssertEqual(r.labels, ["1.MU"])
    }

    func testApostropheTitleKeptVerbatim() {
        let r = IssueSpec.parse("Director's Cut")
        XCTAssertEqual(r.labels, ["Director's Cut"])
    }

    func testReversedRangeKeptVerbatim() {
        let r = IssueSpec.parse("5-3")
        XCTAssertEqual(r.labels, ["5-3"])
    }

    func testMismatchedPrefixKeptVerbatim() {
        let r = IssueSpec.parse("Annual 1-Batman 3")
        XCTAssertEqual(r.labels, ["Annual 1-Batman 3"])
    }

    func testCapTruncatesAndSetsFlag() {
        let r = IssueSpec.parse("1-99999")
        XCTAssertEqual(r.labels.count, 500)
        XCTAssertEqual(r.labels.first, "1")
        XCTAssertEqual(r.labels.last, "500")
        XCTAssertTrue(r.truncated)
    }

    func testCustomCap() {
        let r = IssueSpec.parse("1-10", cap: 3)
        XCTAssertEqual(r.labels, ["1", "2", "3"])
        XCTAssertTrue(r.truncated)
    }

    func testEmptyStringYieldsNoLabels() {
        let r = IssueSpec.parse("")
        XCTAssertEqual(r.labels, [])
        XCTAssertFalse(r.truncated)
    }

    func testLeadingHashOnPlainToken() {
        let r = IssueSpec.parse("#42")
        XCTAssertEqual(r.labels, ["42"])
    }

    func testSemicolonAndNewlineSeparators() {
        let r = IssueSpec.parse("1; 2\n3")
        XCTAssertEqual(r.labels, ["1", "2", "3"])
    }

    func testLabelIsClippedToLabelLength() {
        let longToken = String(repeating: "x", count: 80)
        let r = IssueSpec.parse(longToken)
        XCTAssertEqual(r.labels.first?.count, Limits.labelLength)
    }

    // MARK: - summarize

    func testSummarizeCollapsesConsecutiveRun() {
        let issues = ["294", "295", "296"].map { Issue(label: $0) }
        XCTAssertEqual(IssueSpec.summarize(issues), "294-296")
    }

    func testSummarizeKeepsNonNumericVerbatim() {
        let issues = [Issue(label: "Annual 1"), Issue(label: "Director's Cut")]
        XCTAssertEqual(IssueSpec.summarize(issues), "Annual 1, Director's Cut")
    }

    func testSummarizeSkipsEmptyLabels() {
        let issues = [Issue(label: ""), Issue(label: "1")]
        XCTAssertEqual(IssueSpec.summarize(issues), "1")
    }

    func testSummarizePreservesZeroPadding() {
        let issues = ["001", "002", "003"].map { Issue(label: $0) }
        XCTAssertEqual(IssueSpec.summarize(issues), "001-003")
    }

    func testSummarizeBreaksRunOnPrefixChange() {
        let issues = [Issue(label: "1"), Issue(label: "2"), Issue(label: "Annual 1")]
        XCTAssertEqual(IssueSpec.summarize(issues), "1-2, Annual 1")
    }

    func testRoundTripForCommonInputs() {
        let inputs = ["294-296, 300, Annual 1", "Annual 1-3", "001-003", "1, 2, 3"]
        for input in inputs {
            let firstPass = IssueSpec.parse(input).labels
            let summary = IssueSpec.summarize(firstPass.map { Issue(label: $0) })
            let secondPass = IssueSpec.parse(summary).labels
            XCTAssertEqual(firstPass, secondPass, "round trip failed for \(input)")
        }
    }

    // MARK: - mergeIssues

    func testMergeIssuesKeepsDoneAndURLByLabel() {
        let existing = [Issue(label: "1", done: true, url: "https://a"), Issue(label: "2", done: false, url: "")]
        let merged = IssueSpec.mergeIssues(existing: existing, labels: ["1", "2", "3"])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0], Issue(label: "1", done: true, url: "https://a"))
        XCTAssertEqual(merged[1], Issue(label: "2", done: false, url: ""))
        XCTAssertEqual(merged[2], Issue(label: "3", done: false, url: ""))
    }

    func testMergeIssuesWithDuplicateLabelsConsumesInOrder() {
        let existing = [Issue(label: "1", done: true), Issue(label: "1", done: false)]
        let merged = IssueSpec.mergeIssues(existing: existing, labels: ["1", "1"])
        XCTAssertEqual(merged[0].done, true)
        XCTAssertEqual(merged[1].done, false)
    }

    func testMergeIssuesEmptyLabelsReturnsSingleBlankIssue() {
        let merged = IssueSpec.mergeIssues(existing: [Issue(label: "1", done: true)], labels: [])
        XCTAssertEqual(merged, [Issue()])
    }
}
