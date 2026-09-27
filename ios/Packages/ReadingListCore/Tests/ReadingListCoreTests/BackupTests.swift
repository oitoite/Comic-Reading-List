import XCTest
@testable import ReadingListCore

final class BackupTests: XCTestCase {

    func testFileNameFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 5
        comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!
        XCTAssertEqual(Backup.fileName(now: date), "unlimited-reading-list-2026-03-05.json")
    }

    func testExportRoundTrip() throws {
        let entry = Entry(series: "Watchmen", issues: [Issue(label: "1", done: true)])
        let list = Playlist(name: "My List", entries: [entry])
        let state = AppState(lists: [list], activeListId: list.id)

        let data = try Backup.export(state: state)
        let imported = Backup.importLists(from: data)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.count, 1)
        XCTAssertEqual(imported?[0].name, "My List")
        XCTAssertEqual(imported?[0].entries[0].series, "Watchmen")
        XCTAssertEqual(imported?[0].entries[0].issues[0].done, true)
    }

    func testExportPayloadShape() throws {
        let state = AppState.blank()
        let data = try Backup.export(state: state)
        let obj = JSON.parse(data) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["version"] as? Int, 2)
        XCTAssertNotNil(obj?["exportedAt"])
        XCTAssertNotNil(obj?["lists"])
        XCTAssertNotNil(obj?["services"])
    }

    func testImportV2Lists() {
        let json = """
        { "lists": [ { "id": "a", "name": "Test", "entries": [ { "series": "X" } ] } ] }
        """
        let lists = Backup.importLists(from: Data(json.utf8))
        XCTAssertEqual(lists?.count, 1)
        XCTAssertEqual(lists?[0].name, "Test")
        XCTAssertEqual(lists?[0].entries[0].series, "X")
    }

    func testImportV1BackupMigrates() {
        let json = """
        {
          "version": 1,
          "lists": [
            { "id": "l1", "name": "Old list", "items": [
              { "series": "Watchmen", "issue": "1-2", "status": "read" }
            ] }
          ]
        }
        """
        let lists = Backup.importLists(from: Data(json.utf8))
        XCTAssertEqual(lists?.count, 1)
        XCTAssertEqual(lists?[0].name, "Old list")
        XCTAssertEqual(lists?[0].entries[0].series, "Watchmen")
        XCTAssertEqual(lists?[0].entries[0].issues.map { $0.label }, ["1", "2"])
        XCTAssertTrue(lists?[0].entries[0].issues.allSatisfy { $0.done } ?? false)
    }

    func testImportReturnsNilForUnreadableFile() {
        XCTAssertNil(Backup.importLists(from: Data("not json".utf8)))
        XCTAssertNil(Backup.importLists(from: Data("{}".utf8)))
        XCTAssertNil(Backup.importLists(from: Data("[]".utf8)))
    }

    func testMergeAssignsFreshIdsAndRenamesDuplicates() {
        var state = AppState.blank()
        let existingName = state.lists[0].name
        let incoming = [Playlist(name: existingName), Playlist(name: "Unique")]
        let incomingIds = Set(incoming.map { $0.id })

        Backup.merge(incoming, into: &state)

        XCTAssertEqual(state.lists.count, 3)
        let imported = Array(state.lists.suffix(2))
        XCTAssertEqual(imported[0].name, existingName + " (imported)")
        XCTAssertEqual(imported[1].name, "Unique")
        XCTAssertFalse(incomingIds.contains(imported[0].id))
        XCTAssertFalse(incomingIds.contains(imported[1].id))
        XCTAssertEqual(state.activeListId, imported[1].id)
    }
}
