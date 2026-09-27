import XCTest
@testable import ReadingListCore

final class MetadataAPITests: XCTestCase {

    // MARK: query

    func testQueryReplacesPunctuationWithSpaces() {
        XCTAssertEqual(MetadataHelpers.query("Kraven's Last Hunt"), "Kraven s Last Hunt")
        XCTAssertEqual(MetadataHelpers.query("Fantastic Four (1998)"), "Fantastic Four 1998")
        XCTAssertEqual(MetadataHelpers.query("Batman: Year One"), "Batman Year One")
    }

    func testQueryCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(MetadataHelpers.query("  spider   man  "), "spider man")
    }

    func testQueryReplacesUnderscoresWithSpace() {
        XCTAssertEqual(MetadataHelpers.query("spider_man_2099"), "spider man 2099")
    }

    func testQueryCapsAt100Characters() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(MetadataHelpers.query(long).count, 100)
    }

    func testQueryKeepsAmpersandQuoteAndAccentedLetters() {
        XCTAssertEqual(MetadataHelpers.query("Cloak & Dagger"), "Cloak & Dagger")
        XCTAssertEqual(MetadataHelpers.query("México"), "México")
    }

    func testQueryHandlesNil() {
        XCTAssertEqual(MetadataHelpers.query(nil), "")
    }

    // MARK: seriesName

    func testSeriesNameStripsTrailingRunYears() {
        XCTAssertEqual(MetadataHelpers.seriesName("Fantastic Four (1998 - 2012)"), "Fantastic Four")
        XCTAssertEqual(MetadataHelpers.seriesName("Fantastic Four (2018 - Present)"), "Fantastic Four")
        XCTAssertEqual(MetadataHelpers.seriesName("Daredevil (1998)"), "Daredevil")
        XCTAssertEqual(MetadataHelpers.seriesName("X-Men (1991 – 2001)"), "X-Men") // en dash
    }

    func testSeriesNameLeavesOtherParentheticalsAlone() {
        XCTAssertEqual(MetadataHelpers.seriesName("Something (Not A Year)"), "Something (Not A Year)")
    }

    // MARK: sortIssuesAscending

    func testSortIssuesAscendingHandlesDecimalsAndUnparseable() {
        let items = [
            MetaIssue(issueNumber: "605.1"),
            MetaIssue(issueNumber: "0.5"),
            MetaIssue(issueNumber: "Annual"),
            MetaIssue(issueNumber: "1")
        ]
        let sorted = MetadataHelpers.sortIssuesAscending(items).map(\.issueNumber)
        XCTAssertEqual(sorted, ["0.5", "1", "605.1", "Annual"])
    }

    // MARK: uniqueLabels

    func testUniqueLabelsDisambiguatesDuplicates() {
        let labels = MetadataHelpers.uniqueLabels(["1", "1", "1", "2"])
        XCTAssertEqual(labels, ["1", "1 (2)", "1 (3)", "2"])
    }

    func testUniqueLabelsDefaultsEmptyToIssue() {
        let labels = MetadataHelpers.uniqueLabels(["", "", "3"])
        XCTAssertEqual(labels, ["Issue", "Issue (2)", "3"])
    }

    // MARK: yearFromSeriesTitle

    func testYearFromSeriesTitle() {
        XCTAssertEqual(MetadataHelpers.yearFromSeriesTitle("Fantastic Four (1998 - 2012)"), 1998)
        XCTAssertNil(MetadataHelpers.yearFromSeriesTitle("Fantastic Four"))
        XCTAssertNil(MetadataHelpers.yearFromSeriesTitle(nil))
    }

    // MARK: httpsURL / marvelCoverURL

    func testHttpsURLUpgradesHttp() {
        XCTAssertEqual(MetadataHelpers.httpsURL("http://example.com/a.jpg"), "https://example.com/a.jpg")
        XCTAssertEqual(MetadataHelpers.httpsURL("https://example.com/a.jpg"), "https://example.com/a.jpg")
    }

    func testHttpsURLRejectsNonHTTP() {
        XCTAssertEqual(MetadataHelpers.httpsURL("javascript:alert(1)"), "")
    }

    func testMarvelCoverURLBuildsPortraitVariantByDefault() {
        let url = MetadataHelpers.marvelCoverURL(path: "http://i.annihil.us/u/prod/marvel/i/mg/1/00/abc", extension: "jpg")
        XCTAssertEqual(url, "https://i.annihil.us/u/prod/marvel/i/mg/1/00/abc/portrait_uncanny.jpg")
    }

    func testMarvelCoverURLHonorsVariant() {
        let url = MetadataHelpers.marvelCoverURL(path: "https://i.annihil.us/x", extension: "png", variant: "standard_large")
        XCTAssertEqual(url, "https://i.annihil.us/x/standard_large.png")
    }

    func testMarvelCoverURLBlanksOutImageNotAvailable() {
        let url = MetadataHelpers.marvelCoverURL(path: "https://i.annihil.us/u/prod/marvel/i/mg/b/40/image_not_available", extension: "jpg")
        XCTAssertEqual(url, "")
    }

    func testMarvelCoverURLBlanksOutMissingPath() {
        XCTAssertEqual(MetadataHelpers.marvelCoverURL(path: nil, extension: "jpg"), "")
        XCTAssertEqual(MetadataHelpers.marvelCoverURL(path: "", extension: "jpg"), "")
    }

    // MARK: credits

    func testCreditsMatchesWriterAndArtistRoles() {
        let creators: [Any] = [
            ["name": "Chris Claremont", "role": "writer"],
            ["name": "John Byrne", "role": "penciler"],
        ]
        let credits = MetadataHelpers.credits(from: creators)
        XCTAssertEqual(credits.writer, "Chris Claremont")
        XCTAssertEqual(credits.artist, "John Byrne")
    }

    func testCreditsMatchesPencillerAndArtistSpellingVariants() {
        let pencillerCredits = MetadataHelpers.credits(from: [["name": "A", "role": "penciller (cover)"]])
        XCTAssertEqual(pencillerCredits.artist, "A")

        let artistCredits = MetadataHelpers.credits(from: [["name": "B", "role": "cover artist"]])
        XCTAssertEqual(artistCredits.artist, "B")
    }

    func testCreditsIgnoresUnmatchedRolesAndTakesFirstMatch() {
        let credits = MetadataHelpers.credits(from: [
            ["name": "Editor Only", "role": "editor"],
            ["name": "First Writer", "role": "writer"],
            ["name": "Second Writer", "role": "writer"]
        ])
        XCTAssertEqual(credits.writer, "First Writer")
        XCTAssertEqual(credits.artist, "")
    }

    func testCreditsHandlesNilCreators() {
        let credits = MetadataHelpers.credits(from: nil)
        XCTAssertEqual(credits.writer, "")
        XCTAssertEqual(credits.artist, "")
    }

    // MARK: entryFromMeta

    func testEntryFromMetaBuildsSortedLabeledEntry() {
        let series = MetaSeries(id: 2001, title: "Fantastic Four (1998 - 2012)", name: "Fantastic Four", hits: 3)
        let items = [
            MetaIssue(issueNumber: "2", detailUrl: "https://www.marvel.com/comics/issue/2/x", unlimitedDate: "2020", yearPage: 1998),
            MetaIssue(issueNumber: "1", detailUrl: "https://www.marvel.com/comics/issue/1/x", unlimitedDate: nil, yearPage: 1998)
        ]
        let entry = MetadataHelpers.entryFromMeta(series: series, items: items, onlyUnlimited: false)
        XCTAssertEqual(entry.series, "Fantastic Four")
        XCTAssertEqual(entry.publisher, "Marvel")
        XCTAssertEqual(entry.service, "mu")
        XCTAssertEqual(entry.year, 1998)
        XCTAssertEqual(entry.issues.map(\.label), ["1", "2"])
        XCTAssertEqual(entry.issues.map(\.url), [
            "https://www.marvel.com/comics/issue/1/x",
            "https://www.marvel.com/comics/issue/2/x"
        ])
    }

    func testEntryFromMetaOnlyUnlimitedFiltersMissingDate() {
        let series = MetaSeries(id: 1, title: "Some Series", name: "Some Series", hits: 1)
        let items = [
            MetaIssue(issueNumber: "1", unlimitedDate: "2020-01-01"),
            MetaIssue(issueNumber: "2", unlimitedDate: nil)
        ]
        let entry = MetadataHelpers.entryFromMeta(series: series, items: items, onlyUnlimited: true)
        XCTAssertEqual(entry.issues.map(\.label), ["1"])
    }

    // MARK: marvelIssueID

    func testMarvelIssueIDExtractsDigitsFromURL() {
        XCTAssertEqual(MetadataHelpers.marvelIssueID(from: "https://www.marvel.com/comics/issue/12345/fantastic_four_1998_1"), "12345")
    }

    func testMarvelIssueIDReturnsNilWhenNotPresent() {
        XCTAssertNil(MetadataHelpers.marvelIssueID(from: "https://www.marvel.com/comics/series/2001"))
    }

    // MARK: errorMessage

    func testErrorMessageUsesDetailString() {
        let msg = MetadataHelpers.errorMessage(body: ["detail": "Bad query"], status: 400)
        XCTAssertEqual(msg, "Bad query")
    }

    func testErrorMessageJoinsDetailArray() {
        let msg = MetadataHelpers.errorMessage(body: ["detail": [["msg": "field required"], ["msg": "too short"]]], status: 422)
        XCTAssertEqual(msg, "field required; too short")
    }

    func testErrorMessageRateLimited() {
        XCTAssertEqual(MetadataHelpers.errorMessage(body: nil, status: 429),
                        "Too many requests — the API allows 60 a minute. Wait a moment and try again.")
    }

    func testErrorMessageServerError() {
        XCTAssertEqual(MetadataHelpers.errorMessage(body: nil, status: 503),
                        "The metadata API had an error on that query. Try different wording.")
    }

    func testErrorMessageGenericStatus() {
        XCTAssertEqual(MetadataHelpers.errorMessage(body: nil, status: 404), "The metadata API returned HTTP 404.")
    }

    // MARK: searchSeries validation (no network)

    func testSearchSeriesRejectsShortQueries() async {
        let api = MetadataAPI()
        do {
            _ = try await api.searchSeries("a")
            XCTFail("expected to throw")
        } catch {
            XCTAssertEqual((error as? MetadataError)?.message, "Type at least two letters.")
        }
    }

    // MARK: parseSearch / parseIssues fixtures (no network)

    private func loadFixture(_ name: String) throws -> Any {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("missing fixture \(name)")
        }
        let data = try Data(contentsOf: url)
        return JSON.parse(data)!
    }

    func testParseSearchFoldsItemsBySeriesPreservingOrder() throws {
        let body = try loadFixture("search_issues")
        let result = MetadataAPI.parseSearch(body)
        XCTAssertEqual(result.series.map(\.id), [2001, 3002])
        XCTAssertEqual(result.series[0].title, "Fantastic Four (1998 - 2012)")
        XCTAssertEqual(result.series[0].name, "Fantastic Four")
        XCTAssertEqual(result.series[0].hits, 2)
        XCTAssertEqual(result.series[1].hits, 1)
        XCTAssertFalse(result.capped)
    }

    func testParseSearchMarksCappedAtLimit() {
        let items = (0..<200).map { i -> [String: Any] in ["seriesId": i, "seriesName": "S\(i)"] }
        let result = MetadataAPI.parseSearch(["items": items])
        XCTAssertTrue(result.capped)
    }

    func testParseIssuesReadsPaginationFields() throws {
        let body = try loadFixture("series_issues")
        let page = MetadataAPI.parseIssuesPage(body)
        XCTAssertEqual(page.items.count, 4)
        XCTAssertEqual(page.total, 4)
        XCTAssertEqual(page.seriesName, "Fantastic Four (1998 - 2012)")
        XCTAssertFalse(page.hasNext)
        XCTAssertEqual(page.items.first?.issueNumber, "3")
        XCTAssertEqual(page.items.first?.id, 11113)
    }

    func testIssueDetailParsesCoverAndCredits() {
        let body: [String: Any] = [
            "cover": ["path": "http://i.annihil.us/u/x", "extension": "jpg"],
            "description": "A great issue",
            "pageCount": 22,
            "creators": [
                ["name": "Writer Person", "role": "writer"],
                ["name": "Artist Person", "role": "artist"]
            ]
        ]
        let detail = MetadataAPI.parseIssueDetail(body)
        XCTAssertEqual(detail.cover, "https://i.annihil.us/u/x/portrait_uncanny.jpg")
        XCTAssertEqual(detail.description, "A great issue")
        XCTAssertEqual(detail.pageCount, 22)
        XCTAssertEqual(detail.writer, "Writer Person")
        XCTAssertEqual(detail.artist, "Artist Person")
    }
}
