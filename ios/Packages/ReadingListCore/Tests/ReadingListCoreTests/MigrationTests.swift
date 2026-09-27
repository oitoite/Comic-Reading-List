import XCTest
@testable import ReadingListCore

final class MigrationTests: XCTestCase {

    func testLooksLikeV1ByVersionNumber() {
        XCTAssertTrue(V1Migration.looksLikeV1(["version": 1, "lists": []]))
    }

    func testLooksLikeV1ByItemsArray() {
        let raw: [String: Any] = ["lists": [["id": "a", "items": []]]]
        XCTAssertTrue(V1Migration.looksLikeV1(raw))
    }

    func testDoesNotLookLikeV1() {
        let raw: [String: Any] = ["version": 2, "lists": [["id": "a", "entries": []]]]
        XCTAssertFalse(V1Migration.looksLikeV1(raw))
        XCTAssertFalse(V1Migration.looksLikeV1(nil))
        XCTAssertFalse(V1Migration.looksLikeV1("not a dict"))
    }

    func testMigrateSeriesAndTitleWithReadStatus() {
        let raw: [String: Any] = [
            "activeListId": "list-1",
            "lists": [
                [
                    "id": "list-1",
                    "name": "My List",
                    "items": [
                        [
                            "id": "item-1",
                            "series": "The Amazing Spider-Man",
                            "title": "Kraven's Last Hunt",
                            "issue": "1-3",
                            "status": "read",
                            "writer": "J.M. DeMatteis",
                            "rating": 5
                        ]
                    ]
                ]
            ]
        ]

        let state = V1Migration.migrate(raw)
        XCTAssertEqual(state.lists.count, 1)
        let entry = state.lists[0].entries[0]
        XCTAssertEqual(entry.series, "The Amazing Spider-Man")
        XCTAssertEqual(entry.title, "Kraven's Last Hunt")
        XCTAssertEqual(entry.issues.map { $0.label }, ["1", "2", "3"])
        XCTAssertTrue(entry.issues.allSatisfy { $0.done })
        XCTAssertEqual(entry.writer, "J.M. DeMatteis")
        XCTAssertEqual(entry.rating, 5)
        XCTAssertEqual(state.activeListId, "list-1")
        XCTAssertEqual(state.lists[0].service, Service.marvelUnlimitedID)
    }

    func testMigrateTitleOnlyBecomesSeriesWithNoArcTitle() {
        let raw: [String: Any] = [
            "lists": [
                ["id": "l1", "items": [["title": "Watchmen"]]]
            ]
        ]
        let state = V1Migration.migrate(raw)
        let entry = state.lists[0].entries[0]
        XCTAssertEqual(entry.series, "Watchmen")
        XCTAssertEqual(entry.title, "")
    }

    func testMigrateReadingStatusSetsStartedNotDone() {
        let raw: [String: Any] = [
            "lists": [
                ["id": "l1", "items": [["series": "X", "issue": "1-2", "status": "reading"]]]
            ]
        ]
        let state = V1Migration.migrate(raw)
        let entry = state.lists[0].entries[0]
        XCTAssertTrue(entry.started)
        XCTAssertTrue(entry.issues.allSatisfy { !$0.done })
        XCTAssertEqual(entry.status, .reading)
    }

    func testMigrateEmptyIssueFieldYieldsOneEmptyLabel() {
        let raw: [String: Any] = [
            "lists": [
                ["id": "l1", "items": [["series": "Watchmen"]]]
            ]
        ]
        let state = V1Migration.migrate(raw)
        XCTAssertEqual(state.lists[0].entries[0].issues.map { $0.label }, [""])
    }

    func testMigratePreservesThemeAndView() {
        let raw: [String: Any] = [
            "lists": [["id": "l1", "items": []]],
            "prefs": ["theme": "light", "view": "grid"]
        ]
        let state = V1Migration.migrate(raw)
        XCTAssertEqual(state.prefs.theme, .light)
        XCTAssertEqual(state.prefs.view, .grid)
        XCTAssertEqual(state.prefs.sort, .order)
    }

    func testMigrateDefaultsThemeToDark() {
        let raw: [String: Any] = ["lists": [["id": "l1", "items": []]]]
        let state = V1Migration.migrate(raw)
        XCTAssertEqual(state.prefs.theme, .dark)
        XCTAssertEqual(state.prefs.view, .list)
    }

    func testMigrateWithNoListsProducesBlankState() {
        let state = V1Migration.migrate([String: Any]())
        XCTAssertEqual(state.lists.count, 1)
        XCTAssertNotNil(state.activeListId)
        XCTAssertEqual(state.activeListId, state.lists[0].id)
    }
}
