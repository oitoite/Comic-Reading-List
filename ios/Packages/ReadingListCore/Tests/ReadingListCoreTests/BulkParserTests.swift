import XCTest
@testable import ReadingListCore

final class BulkParserTests: XCTestCase {

    func testReadmeExample() {
        let text = """
        The Amazing Spider-Man #294-296 | Kraven's Last Hunt
        Web of Spider-Man #31-32
        Watchmen
        """
        let r = BulkParser.parse(text)
        XCTAssertEqual(r.entries.count, 3)
        XCTAssertEqual(r.issueCount, 6)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertFalse(r.truncated)

        XCTAssertEqual(r.entries[0].series, "The Amazing Spider-Man")
        XCTAssertEqual(r.entries[0].title, "Kraven's Last Hunt")
        XCTAssertEqual(r.entries[0].issues.map { $0.label }, ["294", "295", "296"])

        XCTAssertEqual(r.entries[1].series, "Web of Spider-Man")
        XCTAssertEqual(r.entries[1].issues.map { $0.label }, ["31", "32"])

        XCTAssertEqual(r.entries[2].series, "Watchmen")
        XCTAssertEqual(r.entries[2].issues.count, 1)
        XCTAssertEqual(r.entries[2].issues[0].label, "")
        XCTAssertTrue(r.entries[2].isSingleBook)
    }

    func testBlankLinesAndCommentsAreIgnored() {
        let text = """

        // a comment
        Watchmen

        // another comment
        """
        let r = BulkParser.parse(text)
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(r.entries[0].series, "Watchmen")
    }

    func testBarWithNoHashIsOneUnnumberedBookWithTitle() {
        let r = BulkParser.parse("Some Book | Some arc")
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(r.entries[0].series, "Some Book")
        XCTAssertEqual(r.entries[0].title, "Some arc")
        XCTAssertEqual(r.entries[0].issues.map { $0.label }, [""])
    }

    func testBlankSeriesBeforeHashIsSkipped() {
        let r = BulkParser.parse("#1-3")
        XCTAssertEqual(r.entries.count, 0)
        XCTAssertEqual(r.skipped, 1)
    }

    func testLastHashIsTheSplitPoint() {
        let r = BulkParser.parse("Batman: No Man's Land #1 #5-7")
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(r.entries[0].series, "Batman: No Man's Land #1")
        XCTAssertEqual(r.entries[0].issues.map { $0.label }, ["5", "6", "7"])
    }

    func testTruncatesAtMaxBulkLines() {
        let lines = (1...(Limits.maxBulkLines + 20)).map { "Series \($0)" }
        let r = BulkParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(r.entries.count, Limits.maxBulkLines)
        XCTAssertTrue(r.truncated)
    }

    func testEmptyTextYieldsNoEntries() {
        let r = BulkParser.parse("")
        XCTAssertEqual(r.entries.count, 0)
        XCTAssertEqual(r.issueCount, 0)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertFalse(r.truncated)
    }
}
