import XCTest
@testable import ReadingListCore

final class StateStoreTests: XCTestCase {

    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingListCoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSaveLoadRoundTrip() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStateStore(directory: dir)

        var state = AppState.blank()
        state.lists[0].entries.append(Entry(series: "Fantastic Four", issues: [Issue(label: "1", done: true)]))
        state.prefs.metaApi = "https://example.com"

        try store.save(state)
        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded.lists.count, 1)
        XCTAssertEqual(loaded.lists[0].entries.count, 1)
        XCTAssertEqual(loaded.lists[0].entries[0].series, "Fantastic Four")
        XCTAssertEqual(loaded.lists[0].entries[0].issues[0].done, true)
        XCTAssertEqual(loaded.prefs.metaApi, "https://example.com")
        XCTAssertEqual(loaded.activeListId, state.activeListId)
    }

    func testLoadReturnsNilWhenFileMissing() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStateStore(directory: dir)
        XCTAssertNil(try store.load())
    }

    func testLoadQuarantinesCorruptFileAndReturnsNil() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileName = "playlists.v2.json"
        let store = FileStateStore(directory: dir, fileName: fileName)

        let fileURL = dir.appendingPathComponent(fileName)
        try Data("{ this is not valid JSON".utf8).write(to: fileURL)

        let loaded = try store.load()
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("\(fileName).corrupt-") })
    }

    func testSaveOverwritesPreviousContent() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStateStore(directory: dir)

        try store.save(AppState.blank())
        var second = AppState.blank()
        second.lists[0].name = "Second Save"
        try store.save(second)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.lists[0].name, "Second Save")
    }

    func testDefaultDirectoryIsCreatedAndWritable() {
        let dir = FileStateStore.defaultDirectory()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }
}
