import XCTest
@testable import ReadingListCore

/// `share_from_web.txt` was produced by the web app's own `packList` + `b64urlEncode`
/// (extracted verbatim from assets/app.js and run under Node with a gzip stream), from a
/// playlist that itself had been decoded from a Swift-made code. Decoding it here closes
/// the loop: Swift → JS → Swift with nothing lost.
final class WebInteropTests: XCTestCase {
    func testDecodesShareLinkMadeByTheWebApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "share_from_web", withExtension: "txt", subdirectory: "Fixtures"))
        let code = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(code.hasPrefix("g"), "the web app gzips when the browser can")

        let list = try XCTUnwrap(ShareCodec.unpack(try ShareCodec.decode(code)))
        XCTAssertEqual(list.name, "Interop <b>list</b>")
        XCTAssertEqual(list.service, "dcui")
        XCTAssertEqual(list.entries.count, 2)

        let spidey = list.entries[0]
        XCTAssertEqual(spidey.series, "The Amazing Spider-Man")
        XCTAssertEqual(spidey.title, "Kraven's Last Hunt")
        XCTAssertEqual(spidey.issues.map(\.label), ["294", "295", "296"])
        XCTAssertEqual(spidey.issues.map(\.done), [true, false, true])
        XCTAssertEqual(spidey.issues[0].url, "https://www.marvel.com/comics/issue/1/x")
        XCTAssertEqual(spidey.issues[2].url, "", "a javascript: link never survives either side")
        XCTAssertTrue(spidey.started)
        XCTAssertEqual(spidey.year, 1987)
        XCTAssertEqual(spidey.tags, ["classic", "spidey"])
        XCTAssertEqual(spidey.rating, 5)
        XCTAssertEqual(spidey.notes, "Ünïcödé & \"quotes\"")
        XCTAssertEqual(spidey.status, .reading)

        let watchmen = list.entries[1]
        XCTAssertEqual(watchmen.series, "Watchmen")
        XCTAssertTrue(watchmen.isSingleBook)
        XCTAssertEqual(watchmen.year, 1986)
    }
}

extension WebInteropTests {
    /// `v1_migrated_by_web.json` is what the site's own `finalize(migrateV1(...))` (run under
    /// Node) produced from `v1_backup.json`. Swift must land on exactly the same entries.
    func testV1MigrationMatchesTheWebAppByteForByte() throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let raw = JSON.parse(try Data(contentsOf: fixtures.appendingPathComponent("v1_backup.json")))
        let expected = try XCTUnwrap(JSON.parse(try Data(contentsOf: fixtures.appendingPathComponent("v1_migrated_by_web.json"))) as? [String: Any])

        XCTAssertTrue(V1Migration.looksLikeV1(raw))
        let state = V1Migration.migrate(raw)

        XCTAssertEqual(state.prefs.theme.rawValue, expected["theme"] as? String)
        XCTAssertEqual(state.prefs.view.rawValue, expected["view"] as? String)
        XCTAssertEqual(state.prefs.sort.rawValue, expected["sort"] as? String)

        let expectedLists = try XCTUnwrap(expected["lists"] as? [[String: Any]])
        XCTAssertEqual(state.lists.count, expectedLists.count)
        for (list, want) in zip(state.lists, expectedLists) {
            XCTAssertEqual(list.id, want["id"] as? String)
            XCTAssertEqual(list.name, want["name"] as? String)
            XCTAssertEqual(list.service, want["service"] as? String)
            let wantEntries = try XCTUnwrap(want["entries"] as? [[String: Any]])
            XCTAssertEqual(list.entries.count, wantEntries.count)
            for (entry, w) in zip(list.entries, wantEntries) {
                XCTAssertEqual(entry.series, w["series"] as? String)
                XCTAssertEqual(entry.title, w["title"] as? String)
                XCTAssertEqual(entry.started, w["started"] as? Bool)
                XCTAssertEqual(entry.writer, w["writer"] as? String)
                XCTAssertEqual(entry.artist, w["artist"] as? String)
                XCTAssertEqual(entry.publisher, w["publisher"] as? String)
                XCTAssertEqual(entry.year, w["year"] as? Int)
                XCTAssertEqual(entry.service, w["service"] as? String)
                XCTAssertEqual(entry.url, w["url"] as? String)
                XCTAssertEqual(entry.cover, w["cover"] as? String)
                XCTAssertEqual(entry.tags, w["tags"] as? [String])
                XCTAssertEqual(entry.notes, w["notes"] as? String)
                XCTAssertEqual(entry.rating, w["rating"] as? Int)
                XCTAssertEqual(entry.addedAt, Sanitizer.millis(w["addedAt"], fallback: -1))
                let issues = try XCTUnwrap(w["issues"] as? [[String: Any]])
                XCTAssertEqual(entry.issues.map(\.label), issues.map { $0["label"] as? String ?? "?" })
                XCTAssertEqual(entry.issues.map(\.done), issues.map { $0["done"] as? Bool ?? false })
                XCTAssertEqual(entry.issues.map(\.url), issues.map { $0["url"] as? String ?? "?" })
            }
        }
    }
}
