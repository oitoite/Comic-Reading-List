import XCTest
@testable import ReadingListCore

final class SmokeTests: XCTestCase {
    func testBlankStateHasOneList() {
        let s = AppState.blank()
        XCTAssertEqual(s.lists.count, 1)
        XCTAssertEqual(s.activeListId, s.lists[0].id)
    }

    func testSanitizerRejectsBadURLsAndYears() {
        let e = Sanitizer.entry(["series": "  X ", "year": "", "url": "javascript:alert(1)", "cover": "https://a/b.jpg", "rating": 9])
        XCTAssertEqual(e.series, "X")
        XCTAssertNil(e.year)
        XCTAssertEqual(e.url, "")
        XCTAssertEqual(e.cover, "https://a/b.jpg")
        XCTAssertEqual(e.rating, 5)
        XCTAssertEqual(e.issues.count, 1)
    }
}
