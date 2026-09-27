import XCTest
@testable import ReadingListCore

final class ShareCodecTests: XCTestCase {

    // MARK: base64url

    func testBase64urlRoundTrip() throws {
        for length in 0...8 {
            let data = Data((0..<length).map { UInt8($0 * 37 % 256) })
            let encoded = ShareCodec.base64urlEncode(data)
            XCTAssertFalse(encoded.contains("+"))
            XCTAssertFalse(encoded.contains("/"))
            XCTAssertFalse(encoded.contains("="))
            let decoded = try ShareCodec.base64urlDecode(encoded)
            XCTAssertEqual(decoded, data)
        }
    }

    func testBase64urlDecodeToleratesMissingPadding() throws {
        // "f" -> base64 "Zg==" -> base64url without padding "Zg"
        let decoded = try ShareCodec.base64urlDecode("Zg")
        XCTAssertEqual(decoded, Data("f".utf8))
    }

    func testBase64urlDecodeRejectsInvalidInput() {
        XCTAssertThrowsError(try ShareCodec.base64urlDecode("not valid base64!!! ***"))
    }

    // MARK: pack / unpack round trip

    private func sampleList(withProgress: Bool) -> Playlist {
        var issues = [
            Issue(label: "1", done: true, url: "https://example.com/issue/1"),
            Issue(label: "2", done: false, url: ""),
            Issue(label: "3", done: withProgress, url: "https://example.com/issue/3")
        ]
        if !withProgress {
            issues = issues.map { Issue(label: $0.label, done: false, url: $0.url) }
        }
        let entry = Entry(
            series: "Fantastic Four",
            title: "Kraven's Last Hunt",
            issues: issues,
            started: withProgress,
            writer: "Stan Lee",
            artist: "Jack Kirby",
            publisher: "Marvel",
            year: 1998,
            service: "mu",
            url: "https://example.com/entry",
            cover: "https://example.com/cover.jpg",
            tags: ["classic", "team"],
            notes: "Great arc",
            rating: 4
        )
        return Playlist(name: "My List", service: "mu", entries: [entry])
    }

    func testPackEncodeDecodeUnpackRoundTripWithoutProgress() throws {
        let list = sampleList(withProgress: false)
        let packed = ShareCodec.pack(list, includeProgress: false)
        let code = try ShareCodec.encode(packed)
        let decoded = try ShareCodec.decode(code)
        let unpacked = try XCTUnwrap(ShareCodec.unpack(decoded))

        XCTAssertEqual(unpacked.name, "My List")
        XCTAssertEqual(unpacked.service, "mu")
        XCTAssertEqual(unpacked.entries.count, 1)
        let entry = unpacked.entries[0]
        XCTAssertEqual(entry.series, "Fantastic Four")
        XCTAssertEqual(entry.title, "Kraven's Last Hunt")
        XCTAssertEqual(entry.issues.map(\.label), ["1", "2", "3"])
        // Progress was not included, so no issue should read as done even though the
        // source list had one ticked, and `started` must not survive either.
        XCTAssertTrue(entry.issues.allSatisfy { !$0.done })
        XCTAssertFalse(entry.started)
        XCTAssertEqual(entry.issues[0].url, "https://example.com/issue/1")
        XCTAssertEqual(entry.issues[1].url, "")
        XCTAssertEqual(entry.writer, "Stan Lee")
        XCTAssertEqual(entry.artist, "Jack Kirby")
        XCTAssertEqual(entry.publisher, "Marvel")
        XCTAssertEqual(entry.year, 1998)
        XCTAssertEqual(entry.url, "https://example.com/entry")
        XCTAssertEqual(entry.cover, "https://example.com/cover.jpg")
        XCTAssertEqual(entry.tags, ["classic", "team"])
        XCTAssertEqual(entry.notes, "Great arc")
        XCTAssertEqual(entry.rating, 4)
    }

    func testPackEncodeDecodeUnpackRoundTripWithProgress() throws {
        let list = sampleList(withProgress: true)
        let packed = ShareCodec.pack(list, includeProgress: true)
        let code = try ShareCodec.encode(packed)
        let decoded = try ShareCodec.decode(code)
        let unpacked = try XCTUnwrap(ShareCodec.unpack(decoded))

        let entry = unpacked.entries[0]
        XCTAssertTrue(entry.started)
        XCTAssertEqual(entry.issues.map(\.done), [true, false, true])
    }

    func testPackedObjectHasNoEmptyOptionalKeys() throws {
        let entry = Entry(series: "Bare", issues: [Issue(label: "1")])
        let list = Playlist(name: "Bare List", entries: [entry])
        let packed = ShareCodec.pack(list, includeProgress: true)
        let json = try JSONSerialization.data(withJSONObject: packed, options: [.sortedKeys])
        let text = String(data: json, encoding: .utf8)!

        for key in ["\"t\"", "\"iu\"", "\"d\"", "\"st\"", "\"w\"", "\"a\"", "\"p\"",
                    "\"y\"", "\"sv\"", "\"u\"", "\"c\"", "\"g\"", "\"o\"", "\"r\""] {
            XCTAssertFalse(text.contains(key), "expected \(key) to be absent from \(text)")
        }
        XCTAssertTrue(text.contains("\"s\":\"Bare\""))
        XCTAssertTrue(text.contains("\"i\":[\"1\"]"))
    }

    func testEncodeDecodeUsesGzipPrefix() throws {
        let list = sampleList(withProgress: false)
        let code = try ShareCodec.encode(ShareCodec.pack(list, includeProgress: false))
        XCTAssertTrue(code.hasPrefix("g"))
    }

    // MARK: hostile payloads

    func testUnpackRejectsNonObjectInput() {
        XCTAssertNil(ShareCodec.unpack(nil))
        XCTAssertNil(ShareCodec.unpack("just a string"))
        XCTAssertNil(ShareCodec.unpack([1, 2, 3]))
        XCTAssertNil(ShareCodec.unpack(42))
    }

    func testUnpackStripsJavascriptURLs() {
        let obj: [String: Any] = [
            "v": 2, "n": "Evil", "s": "mu",
            "e": [
                ["s": "Series", "i": ["1"], "u": "javascript:alert(1)",
                 "c": "javascript:alert(2)",
                 "iu": ["0": "javascript:alert(3)"]]
            ]
        ]
        let list = ShareCodec.unpack(obj)!
        let entry = list.entries[0]
        XCTAssertEqual(entry.url, "")
        XCTAssertEqual(entry.cover, "")
        XCTAssertEqual(entry.issues[0].url, "")
    }

    func testUnpackCapsEntriesAt500() {
        let manyEntries: [[String: Any]] = (0..<10_000).map { i in ["s": "Series \(i)", "i": ["1"]] }
        let obj: [String: Any] = ["v": 2, "n": "Big", "s": "mu", "e": manyEntries]
        let list = ShareCodec.unpack(obj)!
        XCTAssertEqual(list.entries.count, Limits.maxShareEntries)
    }

    func testUnpackClipsLabels() {
        let longLabel = String(repeating: "x", count: 500)
        let obj: [String: Any] = ["v": 2, "n": "Long", "s": "mu",
                                   "e": [["s": "Series", "i": [longLabel]]]]
        let list = ShareCodec.unpack(obj)!
        XCTAssertEqual(list.entries[0].issues[0].label.count, Limits.labelLength)
    }

    func testUnpackDoneIgnoresNonIntegerIndices() {
        let obj: [String: Any] = [
            "v": 2, "n": "Done", "s": "mu",
            "e": [["s": "Series", "i": ["1", "2", "3", "4"], "d": [0, "1", 2.5, 3]]]
        ]
        let list = ShareCodec.unpack(obj)!
        let issues = list.entries[0].issues
        XCTAssertEqual(issues.map(\.done), [true, false, false, true])
    }

    func testUnpackDefaultsNameAndService() {
        let obj: [String: Any] = ["v": 2, "e": []]
        let list = ShareCodec.unpack(obj)!
        XCTAssertEqual(list.name, "Shared list")
        XCTAssertEqual(list.service, "mu")
    }

    func testUnpackHandlesMissingEntriesArray() {
        let list = ShareCodec.unpack(["v": 2, "n": "No entries", "s": "mu"])!
        XCTAssertEqual(list.entries.count, 0)
    }

    // MARK: extractCode

    func testExtractCodeFromHashFragment() {
        let url = URL(string: "https://x/y/#list=abc")!
        XCTAssertEqual(ShareCodec.extractCode(from: url), "abc")
    }

    func testExtractCodeFromCustomSchemeHostPath() {
        let url = URL(string: "unlimitedreadinglist://list/abc")!
        XCTAssertEqual(ShareCodec.extractCode(from: url), "abc")
    }

    func testExtractCodeFromCustomSchemeQuery() {
        let url = URL(string: "unlimitedreadinglist://?list=abc")!
        XCTAssertEqual(ShareCodec.extractCode(from: url), "abc")
    }

    func testExtractCodeFromQueryItem() {
        let url = URL(string: "https://example.com/share?list=xyz789")!
        XCTAssertEqual(ShareCodec.extractCode(from: url), "xyz789")
    }

    func testExtractCodeReturnsNilWhenAbsent() {
        let url = URL(string: "https://x/y/z")!
        XCTAssertNil(ShareCodec.extractCode(from: url))
    }

    // MARK: shareURL

    func testShareURLProducesHashFragment() throws {
        let list = sampleList(withProgress: false)
        let url = try ShareCodec.shareURL(for: list, includeProgress: false, base: ShareCodec.webAppURL)
        XCTAssertTrue(url.absoluteString.hasPrefix(ShareCodec.webAppURL.absoluteString + "#list="))
        let code = ShareCodec.extractCode(from: url)
        XCTAssertNotNil(code)
        let decoded = try ShareCodec.decode(code!)
        XCTAssertNotNil(ShareCodec.unpack(decoded))
    }
}
