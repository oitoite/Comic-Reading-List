import SwiftUI
import ReadingListCore

// MARK: - MarvelSearchView
//
// Port of `marvelDialog` / `runMarvelSearch` / `chooseMarvelSeries` /
// `showMarvelPick` / `addMarvelEntry` (assets/app.js ~1446-1609). Searches the
// third-party Marvel index, lets the user pick a series, fetches its issues, and
// builds an `Entry` preview that can be trimmed before it is added.

@Observable
@MainActor
final class MarvelSearchModel {
    var query = ""
    var status = "Search Marvel by series, arc or issue title — no account or key needed."
    var isError = false
    var isSearching = false
    var results: [MetaSeries] = []

    var selected: MetaSeries?
    var fetchedItems: [MetaIssue] = []
    var isLoadingIssues = false
    var detail: MetaIssueDetail?
    var detailForID: Int?
    var onlyUnlimited = false
    var issuesText = ""
    var isAdding = false

    private var searchTask: Task<Void, Never>?
    private var pickTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    func cancelAll() {
        searchTask?.cancel()
        pickTask?.cancel()
        detailTask?.cancel()
    }

    /// The entry preview for the current selection, filter and fetched detail.
    func previewEntry() -> Entry? {
        guard let selected else { return nil }
        var entry = MetadataHelpers.entryFromMeta(series: selected, items: fetchedItems, onlyUnlimited: onlyUnlimited)
        if let detail {
            entry.cover = detail.cover
            entry.writer = detail.writer
            entry.artist = detail.artist
        }
        return entry
    }

    func recomputeIssuesText() {
        guard let entry = previewEntry() else { return }
        issuesText = IssueSpec.summarize(entry.issues)
    }

    func search(using metadata: MetadataAPI) {
        searchTask?.cancel()
        let q = query
        isSearching = true
        isError = false
        status = "Searching…"
        results = []
        selected = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await metadata.searchSeries(q)
                guard !Task.isCancelled else { return }
                self.results = res.series
                self.isSearching = false
                if res.series.isEmpty {
                    self.status = "Nothing matched \u{201C}\(MetadataHelpers.query(q))\u{201D}."
                } else if res.capped {
                    self.status = "\(Plural.count(res.series.count, "series", "series")) — add a year or issue number to the query if the one you want is missing."
                } else {
                    self.status = "\(Plural.count(res.series.count, "series", "series")) — pick one."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isSearching = false
                self.isError = true
                self.status = self.message(for: error)
            }
        }
    }

    func choose(_ series: MetaSeries, using metadata: MetadataAPI) {
        pickTask?.cancel()
        detailTask?.cancel()
        selected = series
        fetchedItems = []
        detail = nil
        detailForID = nil
        issuesText = ""
        onlyUnlimited = false
        isLoadingIssues = true
        isError = false
        status = "Loading issues for \u{201C}\(series.title)\u{201D}…"

        pickTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await metadata.seriesIssues(series.id) { [weak self] got, total in
                    Task { @MainActor in
                        guard let self, self.selected?.id == series.id else { return }
                        self.status = "Loading issues… \(got) of \(total)"
                    }
                }
                guard !Task.isCancelled, self.selected?.id == series.id else { return }
                self.fetchedItems = res.items
                self.isLoadingIssues = false
                self.recomputeIssuesText()
                self.status = res.total > res.items.count
                    ? "Marvel lists \(res.total) issues; the first \(res.items.count) were fetched."
                    : "Trim the issue list below if you only want part of the run."

                // Cover and credits come from one issue's detail, fetched after the
                // pick is already on screen so it never holds up the UI.
                let ascending = MetadataHelpers.sortIssuesAscending(res.items)
                if let first = ascending.first, let firstID = first.id {
                    self.detailTask = Task { [weak self] in
                        let fetched = try? await metadata.issueDetail(firstID)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard let self, self.selected?.id == series.id else { return }
                            if let fetched {
                                self.detail = fetched
                                self.detailForID = firstID
                                self.recomputeIssuesText()
                            }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoadingIssues = false
                self.isError = true
                self.status = self.message(for: error)
            }
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }
}

struct MarvelSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let listID: String
    @State private var vm = MarvelSearchModel()

    init(listID: String) { self.listID = listID }

    var body: some View {
        NavigationStack {
            Form {
                searchSection
                statusSection
                if vm.selected == nil && !vm.results.isEmpty {
                    resultsSection
                }
                if vm.selected != nil {
                    chosenSection
                }
            }
            .navigationTitle("Find on Marvel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear { vm.cancelAll() }
        }
    }

    // MARK: Sections

    private var searchSection: some View {
        Section {
            HStack {
                TextField("e.g. Fantastic Four 1998", text: $vm.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(runSearch)
                Button("Search", action: runSearch)
                    .disabled(vm.query.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSearching)
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                if vm.isSearching || vm.isLoadingIssues {
                    ProgressView().padding(.trailing, 4)
                }
                Text(vm.status)
                    .foregroundStyle(vm.isError ? .red : .secondary)
                    .font(.footnote)
            }
        }
    }

    private var resultsSection: some View {
        Section("Series") {
            ForEach(vm.results) { series in
                Button {
                    vm.choose(series, using: model.metadata)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.title).foregroundStyle(.primary)
                        Text(Plural.count(series.hits, "match", "matches"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chosenSection: some View {
        if let series = vm.selected, let entry = vm.previewEntry() {
            Section {
                chosenHeader(series: series, entry: entry)
                Toggle("Only issues available on Marvel Unlimited", isOn: Binding(
                    get: { vm.onlyUnlimited },
                    set: { vm.onlyUnlimited = $0; vm.recomputeIssuesText() }
                ))
                TextField("Issue range", text: $vm.issuesText, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(.body, design: .monospaced))
                Button {
                    addToPlaylist()
                } label: {
                    if vm.isAdding {
                        ProgressView()
                    } else {
                        Text("Add to playlist")
                    }
                }
                .disabled(entry.issues.isEmpty || vm.isLoadingIssues || vm.isAdding)
            } header: {
                Text("Issues to add")
            } footer: {
                Text("Trim the range if you only want part of the run.")
            }
        }
    }

    private func chosenHeader(series: MetaSeries, entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: entry.cover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        AppColor.series(entry.series)
                        Text(SeriesInitials.of(entry.series))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: Metrics.rowCoverWidth, height: Metrics.rowCoverWidth / Metrics.coverAspect)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.coverRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(series.title).font(.headline)
                Text(metaLine(entry: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metaLine(entry: Entry) -> String {
        let onMU = vm.fetchedItems.filter { ($0.unlimitedDate?.isEmpty == false) }.count
        var parts: [String] = [Plural.count(entry.issues.count, "issue")]
        parts.append("\(onMU) of \(vm.fetchedItems.count) on Unlimited")
        if let year = entry.year { parts.append(String(year)) }
        let credit = [entry.writer, entry.artist].filter { !$0.isEmpty }.joined(separator: " / ")
        if !credit.isEmpty { parts.append(credit) }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func runSearch() {
        guard !vm.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vm.search(using: model.metadata)
    }

    private func addToPlaylist() {
        guard let entry = vm.previewEntry() else { return }
        let wantedLabels = IssueSpec.parse(vm.issuesText).labels
        var byLabel: [String: Issue] = [:]
        for issue in entry.issues where byLabel[issue.label] == nil {
            byLabel[issue.label] = issue
        }
        let labels = wantedLabels.isEmpty ? entry.issues.map { $0.label } : wantedLabels
        let issues = labels.map { label in
            Issue(label: label, done: false, url: byLabel[label]?.url ?? "")
        }

        vm.isAdding = true
        let firstLabel = issues.first?.label ?? ""
        let firstItem = vm.fetchedItems.first { $0.issueNumber == firstLabel }

        if let firstItem, let id = firstItem.id, id != vm.detailForID {
            Task { @MainActor in
                let detail = try? await model.metadata.issueDetail(id)
                commit(entry: entry, issues: issues, detail: (detail?.cover.isEmpty == false) ? detail : nil)
            }
        } else {
            commit(entry: entry, issues: issues, detail: nil)
        }
    }

    private func commit(entry: Entry, issues: [Issue], detail: MetaIssueDetail?) {
        let newEntry = Entry(
            series: entry.series,
            title: entry.title,
            issues: issues.isEmpty ? [Issue()] : issues,
            writer: detail?.writer ?? entry.writer,
            artist: detail?.artist ?? entry.artist,
            publisher: entry.publisher,
            year: entry.year,
            service: entry.service,
            cover: detail?.cover ?? entry.cover
        )
        model.addEntry(newEntry, to: listID)
        vm.isAdding = false
        dismiss()
    }
}
