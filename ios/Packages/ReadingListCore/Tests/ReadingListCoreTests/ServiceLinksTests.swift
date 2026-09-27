import XCTest
@testable import ReadingListCore

final class ServiceLinksTests: XCTestCase {

    func testEncodeURIComponentMatchesJS() {
        XCTAssertEqual(ServiceLinks.encodeURIComponent("a b"), "a%20b")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("#"), "%23")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("'"), "'")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("("), "(")
        XCTAssertEqual(ServiceLinks.encodeURIComponent(")"), ")")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("Kraven's Last Hunt"), "Kraven's%20Last%20Hunt")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("&"), "%26")
        XCTAssertEqual(ServiceLinks.encodeURIComponent("100%"), "100%25")
    }

    func testServiceResolvesEntryOverrideThenListDefault() {
        let services = Service.defaults
        let list = Playlist(name: "L", service: Service.dcUniverseInfiniteID)
        let withOverride = Entry(series: "X", service: Service.marvelUnlimitedID)
        XCTAssertEqual(ServiceLinks.service(for: withOverride, in: list, services: services).id, Service.marvelUnlimitedID)

        let withoutOverride = Entry(series: "X")
        XCTAssertEqual(ServiceLinks.service(for: withoutOverride, in: list, services: services).id, Service.dcUniverseInfiniteID)
    }

    func testServiceFallsBackToFirstWhenUnknownID() {
        let services = Service.defaults
        let list = Playlist(name: "L", service: "not-a-real-id")
        let entry = Entry(series: "X")
        XCTAssertEqual(ServiceLinks.service(for: entry, in: list, services: services).id, services[0].id)
    }

    func testSearchURLSubstitutesPlaceholders() {
        let service = Service(id: "x", name: "X", template: "https://example.com/search?q={q}&series={series}&issue={issue}")
        let entry = Entry(series: "Kraven's Last Hunt")
        let url = ServiceLinks.searchURL(entry: entry, issueLabel: "1", service: service)
        XCTAssertEqual(url, "https://example.com/search?q=Kraven's%20Last%20Hunt%20%231&series=Kraven's%20Last%20Hunt&issue=1")
    }

    func testSearchURLWithoutIssueLabel() {
        let service = Service(id: "x", name: "X", template: "https://example.com/search?q={q}")
        let entry = Entry(series: "Watchmen")
        let url = ServiceLinks.searchURL(entry: entry, issueLabel: nil, service: service)
        XCTAssertEqual(url, "https://example.com/search?q=Watchmen")
    }

    func testSearchURLReturnsEmptyForUnsafeTemplate() {
        let service = Service(id: "x", name: "X", template: "javascript:alert(1)")
        let entry = Entry(series: "Watchmen")
        XCTAssertEqual(ServiceLinks.searchURL(entry: entry, issueLabel: nil, service: service), "")
    }

    func testSearchURLReturnedUnchangedWhenNoPlaceholders() {
        let service = Service(id: "x", name: "X", template: "https://example.com/fixed")
        let entry = Entry(series: "Watchmen")
        XCTAssertEqual(ServiceLinks.searchURL(entry: entry, issueLabel: "1", service: service), "https://example.com/fixed")
    }

    func testLinkPrefersIssueURLThenEntryURLThenSearch() {
        let list = Playlist(name: "L", service: Service.marvelUnlimitedID)
        let services = Service.defaults

        var entry = Entry(series: "X", url: "https://entry.example")
        let issueWithURL = Issue(label: "1", url: "https://issue.example")
        XCTAssertEqual(ServiceLinks.link(for: entry, issue: issueWithURL, in: list, services: services), "https://issue.example")
        XCTAssertTrue(ServiceLinks.isDirect(entry: entry, issue: issueWithURL))

        let issueNoURL = Issue(label: "1")
        XCTAssertEqual(ServiceLinks.link(for: entry, issue: issueNoURL, in: list, services: services), "https://entry.example")
        XCTAssertTrue(ServiceLinks.isDirect(entry: entry, issue: issueNoURL))

        entry.url = ""
        XCTAssertFalse(ServiceLinks.isDirect(entry: entry, issue: issueNoURL))
        let generated = ServiceLinks.link(for: entry, issue: issueNoURL, in: list, services: services)
        XCTAssertTrue(generated.contains("marvel.com"))
    }

    func testReadURLReturnsValidURL() {
        let list = Playlist(name: "L")
        let entry = Entry(series: "X", url: "https://example.com/x")
        XCTAssertEqual(ServiceLinks.readURL(for: entry, issue: nil, in: list, services: Service.defaults)?.absoluteString, "https://example.com/x")
    }
}
