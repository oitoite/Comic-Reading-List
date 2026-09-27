import Foundation

// MARK: - StateStore
//
// Persistence for the whole app state, mirroring the web app's
// `localStorage['longbox.playlists.v2']` file: one JSON document, sanitized on the way
// back in so a corrupt or foreign file never crashes the app or silently wipes it.

public protocol StateStoring: Sendable {
    func load() throws -> AppState?
    func save(_ state: AppState) throws
}

/// Holds only two immutable values, so it is safe to hand to a detached save task.
public final class FileStateStore: StateStoring, @unchecked Sendable {

    private let directory: URL
    private let fileName: String

    public init(directory: URL, fileName: String = "playlists.v2.json") {
        self.directory = directory
        self.fileName = fileName
    }

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSON.encode(state)
        // Write to a scratch file first, then rename it into place, so a crash
        // mid-write never leaves a half-written state file behind.
        let tempURL = directory.appendingPathComponent(fileName + ".tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            #if canImport(Darwin)
            // replaceItemAt swaps in one step, so there is never a moment with no file at all.
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            #else
            // swift-corelibs-foundation's replaceItemAt is unreliable; remove-then-move is
            // the best Linux can do, and Linux is only the test host.
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            #endif
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }

    public func load() throws -> AppState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            quarantine()
            return nil
        }
        guard let parsed = JSON.parse(data) else {
            quarantine()
            return nil
        }
        return Sanitizer.state(parsed)
    }

    /// Moves a corrupt state file aside instead of throwing it away silently, so it
    /// can still be recovered by hand.
    private func quarantine() {
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        let corruptURL = directory.appendingPathComponent("\(fileName).corrupt-\(millis)")
        try? FileManager.default.moveItem(at: fileURL, to: corruptURL)
    }

    public static func defaultDirectory() -> URL {
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = appSupport.appendingPathComponent("UnlimitedReadingList", isDirectory: true)
            if (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                return dir
            }
        }
        // Application Support is unavailable in some sandboxes (notably plain Linux
        // without a real user domain); fall back to a temp directory rather than crash.
        let fallback = fm.temporaryDirectory.appendingPathComponent("UnlimitedReadingList", isDirectory: true)
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
