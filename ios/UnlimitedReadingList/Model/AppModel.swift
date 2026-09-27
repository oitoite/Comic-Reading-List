import SwiftUI
import Observation
import ReadingListCore

// MARK: - AppModel
//
// The single source of truth for the UI. Every mutation goes through a method here so
// persistence, derived state and toasts stay consistent. Views never write to `state`
// directly. All the rules (status derivation, parsing, links, share codec) live in
// ReadingListCore; this file only sequences them.

@Observable
@MainActor
final class AppModel {

    // MARK: State

    private(set) var state: AppState
    /// Which playlist the entries screen shows. Always a valid id.
    var activeListID: String {
        didSet { if activeListID != oldValue { state.activeListId = activeListID; scheduleSave() } }
    }

    // MARK: Transient UI state

    var filter = EntryFilter()
    var expandedEntryIDs: Set<String> = []
    /// A short confirmation shown at the bottom of the screen; cleared automatically.
    var toast: String?
    /// A playlist decoded from a share link, waiting for the user to accept a copy.
    var incomingShare: Playlist?
    var incomingError: String?

    // MARK: Services

    private let store: StateStoring
    private(set) var metadata: MetadataAPI
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    /// How long a backup can be before the app nags, matching the web app's fortnight.
    static let backupStaleInterval: TimeInterval = 14 * 24 * 3600

    init(store: StateStoring? = nil) {
        let store = store ?? FileStateStore(directory: FileStateStore.defaultDirectory())
        self.store = store
        let loaded = (try? store.load()) ?? nil
        let initial = loaded ?? AppState.blank()
        self.state = initial
        self.activeListID = initial.activeListId ?? initial.lists[0].id
        self.metadata = MetadataAPI(baseURL: URL(string: initial.prefs.metaApi))
    }

    // MARK: - Derived

    var prefs: Prefs { state.prefs }
    var services: [Service] { state.prefs.services }
    var lists: [Playlist] { state.lists }

    var colorScheme: ColorScheme? {
        switch state.prefs.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var activeList: Playlist {
        state.lists.first { $0.id == activeListID } ?? state.lists[0]
    }

    func list(id: String) -> Playlist? {
        state.lists.first { $0.id == id }
    }

    func entry(id: String, in listID: String? = nil) -> Entry? {
        list(id: listID ?? activeListID)?.entries.first { $0.id == id }
    }

    /// Entries of the active playlist after search, status filter and sort.
    var visibleEntries: [Entry] {
        EntryFiltering.visible(activeList.entries, filter: filter, sort: state.prefs.sort)
    }

    /// Reading-order numbers only make sense when the list is in reading order and unfiltered.
    var showsReadingOrderNumbers: Bool {
        state.prefs.sort == .order && filter.query.isEmpty && filter.status == nil
    }

    /// The first entry in reading order with something left to read, and that issue.
    var upNext: (entry: Entry, issue: Issue)? {
        for entry in activeList.entries where entry.status != .finished {
            if let issue = entry.nextIssue { return (entry, issue) }
        }
        return nil
    }

    func service(for entry: Entry, in list: Playlist? = nil) -> Service {
        ServiceLinks.service(for: entry, in: list ?? activeList, services: services)
    }

    func readURL(for entry: Entry, issue: Issue?, in list: Playlist? = nil) -> URL? {
        ServiceLinks.readURL(for: entry, issue: issue, in: list ?? activeList, services: services)
    }

    func isDirect(entry: Entry, issue: Issue?) -> Bool {
        ServiceLinks.isDirect(entry: entry, issue: issue)
    }

    var totalIssues: Int {
        state.lists.reduce(0) { $0 + $1.progress.total }
    }

    /// nil when nothing needs saying; otherwise the sidebar note about backups.
    var backupNote: String? {
        guard totalIssues > 0 else { return nil }
        let last = state.prefs.backedUpAt
        if last == 0 {
            return "This list only exists on this device. Save a copy to keep it somewhere safe."
        }
        let age = Date().timeIntervalSince(Timestamps.date(fromMillis: last))
        if age > Self.backupStaleInterval {
            return "Last saved \(Int(age / 86400)) days ago. Worth saving a fresh copy."
        }
        return nil
    }

    // MARK: - Playlists

    @discardableResult
    func addList(name: String, service: String? = nil) -> Playlist {
        let trimmed = Sanitizer.str(name, Limits.listNameLength)
        let list = Playlist(name: trimmed.isEmpty ? "Untitled list" : trimmed,
                            service: service ?? Service.marvelUnlimitedID)
        state.lists.append(list)
        activeListID = list.id
        expandedEntryIDs = []
        scheduleSave()
        return list
    }

    func renameList(id: String, to name: String) {
        let trimmed = Sanitizer.str(name, Limits.listNameLength)
        guard !trimmed.isEmpty else { return }
        mutateList(id) { $0.name = trimmed }
    }

    func setListService(id: String, service: String) {
        mutateList(id) { $0.service = Sanitizer.serviceID(service, fallback: Service.marvelUnlimitedID) }
    }

    func deleteList(id: String) {
        state.lists.removeAll { $0.id == id }
        if state.lists.isEmpty {
            state.lists = AppState.blank().lists
        }
        if !state.lists.contains(where: { $0.id == activeListID }) {
            activeListID = state.lists[0].id
        }
        expandedEntryIDs = []
        scheduleSave()
    }

    func moveLists(from source: IndexSet, to destination: Int) {
        state.lists.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    // MARK: - Entries

    func addEntry(_ entry: Entry, to listID: String? = nil) {
        let clean = Sanitizer.entry(dictionary(of: entry))
        mutateList(listID ?? activeListID) { $0.entries.append(clean) }
        showToast("Added to \(list(id: listID ?? activeListID)?.name ?? "playlist")")
    }

    func addEntries(_ entries: [Entry], to listID: String? = nil) {
        guard !entries.isEmpty else { return }
        let clean = entries.map { Sanitizer.entry(dictionary(of: $0)) }
        mutateList(listID ?? activeListID) { $0.entries.append(contentsOf: clean) }
        let issues = clean.reduce(0) { $0 + $1.issues.count }
        showToast("Added \(Plural.count(clean.count, "entry", "entries")) · \(Plural.count(issues, "issue"))")
    }

    func updateEntry(_ entry: Entry, in listID: String? = nil) {
        let clean = Sanitizer.entry(dictionary(of: entry))
        mutateEntry(clean.id, in: listID) { $0 = clean }
        showToast("Saved")
    }

    func removeEntry(id: String, from listID: String? = nil) {
        mutateList(listID ?? activeListID) { $0.entries.removeAll { $0.id == id } }
        expandedEntryIDs.remove(id)
        showToast("Removed")
    }

    func moveEntries(from source: IndexSet, to destination: Int, in listID: String? = nil) {
        mutateList(listID ?? activeListID) { $0.entries.move(fromOffsets: source, toOffset: destination) }
    }

    /// Reorder by ids, for drag-and-drop that works on a filtered view: only the
    /// relative order of the moved ids changes; entries not shown stay where they are.
    func reorderEntries(ids: [String], in listID: String? = nil) {
        mutateList(listID ?? activeListID) { list in
            let byID = Dictionary(uniqueKeysWithValues: list.entries.map { ($0.id, $0) })
            var queue = ids.compactMap { byID[$0] }
            let moving = Set(ids)
            list.entries = list.entries.map { moving.contains($0.id) && !queue.isEmpty ? queue.removeFirst() : $0 }
        }
    }

    // MARK: Issue-level progress

    func toggleIssue(entryID: String, index: Int, in listID: String? = nil) {
        mutateEntry(entryID, in: listID) { e in
            guard e.issues.indices.contains(index) else { return }
            e.issues[index].done.toggle()
            if e.issues[index].done { e.started = true }
        }
        Haptics.tick()
    }

    /// Tick the next unread issue. Returns false when the entry is already finished.
    @discardableResult
    func markNextIssue(entryID: String, in listID: String? = nil) -> Bool {
        var changed = false
        mutateEntry(entryID, in: listID) { e in
            guard let idx = e.issues.firstIndex(where: { !$0.done }) else { return }
            e.issues[idx].done = true
            e.started = true
            changed = true
        }
        if changed { Haptics.tick() }
        return changed
    }

    func markAllIssues(entryID: String, in listID: String? = nil) {
        mutateEntry(entryID, in: listID) { e in
            for i in e.issues.indices { e.issues[i].done = true }
            e.started = true
        }
        Haptics.success()
    }

    func clearIssues(entryID: String, in listID: String? = nil) {
        mutateEntry(entryID, in: listID) { e in
            for i in e.issues.indices { e.issues[i].done = false }
            e.started = false
        }
    }

    /// Not started → started; in progress → finished; finished → cleared.
    func cycleEntry(entryID: String, in listID: String? = nil) {
        mutateEntry(entryID, in: listID) { e in
            switch e.status {
            case .unread: e.started = true
            case .reading: for i in e.issues.indices { e.issues[i].done = true }
            case .finished:
                for i in e.issues.indices { e.issues[i].done = false }
                e.started = false
            }
        }
    }

    func setIssueURLs(entryID: String, urls: [String], in listID: String? = nil) {
        mutateEntry(entryID, in: listID) { e in
            for (i, url) in urls.enumerated() where e.issues.indices.contains(i) {
                e.issues[i].url = Sanitizer.safeURL(url)
            }
        }
        showToast("Links saved")
    }

    func toggleExpanded(_ entryID: String) {
        if expandedEntryIDs.contains(entryID) { expandedEntryIDs.remove(entryID) }
        else { expandedEntryIDs.insert(entryID) }
    }

    // MARK: - Preferences

    func setSort(_ sort: EntrySortOrder) { state.prefs.sort = sort; scheduleSave() }
    func setView(_ view: ViewMode) { state.prefs.view = view; scheduleSave() }
    func setTheme(_ theme: Theme) { state.prefs.theme = theme; scheduleSave() }

    func updateServices(_ services: [Service], metaApi: String) {
        state.prefs.services = Sanitizer.services(services.map { ["id": $0.id, "name": $0.name, "template": $0.template] })
        state.prefs.metaApi = Sanitizer.safeURL(metaApi, 300)
        metadata = MetadataAPI(baseURL: URL(string: state.prefs.metaApi))
        scheduleSave()
        showToast("Services saved")
    }

    func resetServices() {
        updateServices(Service.defaults, metaApi: "")
    }

    // MARK: - Backup

    func exportData() throws -> Data {
        try Backup.export(state: state)
    }

    func exportFileName() -> String { Backup.fileName() }

    func markBackedUp() {
        state.prefs.backedUpAt = Timestamps.now()
        scheduleSave()
    }

    /// Adds every playlist in the file alongside the existing ones. Returns how many.
    @discardableResult
    func importBackup(_ data: Data) -> Int {
        guard let incoming = Backup.importLists(from: data), !incoming.isEmpty else {
            showToast("That file has no readable playlists.")
            return 0
        }
        Backup.merge(incoming, into: &state)
        activeListID = state.activeListId ?? state.lists[0].id
        expandedEntryIDs = []
        scheduleSave()
        showToast("Imported \(Plural.count(incoming.count, "playlist"))")
        return incoming.count
    }

    // MARK: - Share links

    func shareURL(for list: Playlist, includeProgress: Bool) throws -> URL {
        try ShareCodec.shareURL(for: list, includeProgress: includeProgress, base: ShareCodec.webAppURL)
    }

    func handleIncoming(url: URL) {
        guard let code = ShareCodec.extractCode(from: url) else { return }
        handleIncoming(code: code)
    }

    /// Also used by "Paste a link" so a link copied from a chat can be imported by hand.
    func handleIncoming(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = ShareCodec.extractCode(from: url) {
            handleIncoming(code: code)
        } else if let range = trimmed.range(of: "list=") {
            handleIncoming(code: String(trimmed[range.upperBound...]))
        } else {
            incomingError = "That doesn't look like a share link."
        }
    }

    private func handleIncoming(code: String) {
        do {
            let object = try ShareCodec.decode(code)
            guard let list = ShareCodec.unpack(object) else {
                incomingError = "That link doesn't contain a playlist."
                return
            }
            incomingShare = list
        } catch {
            incomingError = "That link could not be read."
        }
    }

    func acceptIncoming() {
        guard var list = incomingShare else { return }
        list.id = IDs.make()
        if state.lists.contains(where: { $0.name == list.name }) { list.name += " (copy)" }
        state.lists.append(list)
        activeListID = list.id
        incomingShare = nil
        scheduleSave()
        showToast("Added \(list.name)")
    }

    func dismissIncoming() {
        incomingShare = nil
        incomingError = nil
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Persistence

    private func mutateList(_ id: String, _ change: (inout Playlist) -> Void) {
        guard let idx = state.lists.firstIndex(where: { $0.id == id }) else { return }
        change(&state.lists[idx])
        scheduleSave()
    }

    private func mutateEntry(_ entryID: String, in listID: String?, _ change: (inout Entry) -> Void) {
        mutateList(listID ?? activeListID) { list in
            guard let idx = list.entries.firstIndex(where: { $0.id == entryID }) else { return }
            change(&list.entries[idx])
        }
    }

    /// Writes are coalesced: a burst of issue ticks becomes one file write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = state
        // The outer task inherits the main actor, so reporting a failure is a plain call;
        // only the file write itself hops off to a utility-priority detached task.
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) { try store.save(snapshot) }.value
            } catch {
                showToast("Could not save: \(error.localizedDescription)")
            }
        }
    }

    /// Flush immediately, for scene-phase changes.
    func saveNow() {
        saveTask?.cancel()
        try? store.save(state)
    }

    /// Round-trips a model through JSON so it is clamped by the same sanitizer as any
    /// imported data. Cheap, and it means the UI can never persist an invalid entry.
    private func dictionary(of entry: Entry) -> [String: Any] {
        (try? JSON.encode(entry)).flatMap { JSON.parse($0) as? [String: Any] } ?? [:]
    }
}
