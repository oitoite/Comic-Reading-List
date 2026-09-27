import XCTest
@testable import ReadingListCore

final class FilteringTests: XCTestCase {

    private func entry(_ series: String, title: String = "", writer: String = "", rating: Int = 0,
                        year: Int? = nil, addedAt: Double = 0, issues: [Issue] = [Issue()],
                        started: Bool = false) -> Entry {
        Entry(series: series, title: title, issues: issues, started: started, writer: writer,
              year: year, rating: rating, addedAt: addedAt)
    }

    func testStatusFilter() {
        let unread = entry("A")
        let reading = entry("B", started: true)
        let finished = entry("C", issues: [Issue(label: "1", done: true)])
        let entries = [unread, reading, finished]

        let onlyFinished = EntryFiltering.visible(entries, filter: EntryFilter(status: .finished), sort: .order)
        XCTAssertEqual(onlyFinished.map { $0.series }, ["C"])

        let all = EntryFiltering.visible(entries, filter: EntryFilter(status: nil), sort: .order)
        XCTAssertEqual(all.count, 3)
    }

    func testQueryMatchesAcrossFields() {
        let entries = [
            entry("Watchmen", writer: "Alan Moore"),
            entry("Batman", title: "Year One")
        ]
        let byWriter = EntryFiltering.visible(entries, filter: EntryFilter(query: "moore"), sort: .order)
        XCTAssertEqual(byWriter.map { $0.series }, ["Watchmen"])

        let byTitle = EntryFiltering.visible(entries, filter: EntryFilter(query: "year one"), sort: .order)
        XCTAssertEqual(byTitle.map { $0.series }, ["Batman"])
    }

    func testQueryMatchesIssueLabels() {
        let entries = [entry("X", issues: [Issue(label: "Annual 1")])]
        let matched = EntryFiltering.visible(entries, filter: EntryFilter(query: "annual"), sort: .order)
        XCTAssertEqual(matched.count, 1)
    }

    func testOrderSortKeepsOriginalOrder() {
        let entries = [entry("C"), entry("A"), entry("B")]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .order)
        XCTAssertEqual(sorted.map { $0.series }, ["C", "A", "B"])
    }

    func testAddedSortIsNewestFirstAndStable() {
        let entries = [
            entry("A", addedAt: 100),
            entry("B", addedAt: 300),
            entry("C", addedAt: 300),
            entry("D", addedAt: 200)
        ]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .added)
        XCTAssertEqual(sorted.map { $0.series }, ["B", "C", "D", "A"])
    }

    func testSeriesSortIsCaseInsensitiveThenTitle() {
        let entries = [
            entry("banana", title: "Z"),
            entry("Apple", title: "B"),
            entry("apple", title: "A")
        ]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .series)
        XCTAssertEqual(sorted.map { "\($0.series)-\($0.title)" }, ["apple-A", "Apple-B", "banana-Z"])
    }

    func testTitleSortFallsBackToSeries() {
        let entries = [
            entry("Zeta", title: ""),
            entry("Ignore", title: "Alpha Arc")
        ]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .title)
        XCTAssertEqual(sorted.map { $0.series }, ["Ignore", "Zeta"])
    }

    func testRatingSortDescendingThenSeries() {
        let entries = [entry("B", rating: 3), entry("A", rating: 3), entry("C", rating: 5)]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .rating)
        XCTAssertEqual(sorted.map { $0.series }, ["C", "A", "B"])
    }

    func testYearSortDescendingWithNilAsZero() {
        let entries = [entry("A", year: 2020), entry("B", year: nil), entry("C", year: 1999)]
        let sorted = EntryFiltering.visible(entries, filter: EntryFilter(), sort: .year)
        XCTAssertEqual(sorted.map { $0.series }, ["A", "C", "B"])
    }

    func testProgressSortDescendingByFraction() {
        let mostlyDone = entry("A", issues: [Issue(label: "1", done: true), Issue(label: "2", done: true), Issue(label: "3")])
        let halfDone = entry("B", issues: [Issue(label: "1", done: true), Issue(label: "2")])
        let none = entry("C", issues: [Issue(label: "1")])
        let sorted = EntryFiltering.visible([none, halfDone, mostlyDone], filter: EntryFilter(), sort: .progress)
        XCTAssertEqual(sorted.map { $0.series }, ["A", "B", "C"])
    }
}
