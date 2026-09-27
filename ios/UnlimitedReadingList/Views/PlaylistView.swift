import SwiftUI
import ReadingListCore

// MARK: - PlaylistView
//
// The detail column: one playlist's entries, searchable and filterable, with the
// "Up next" card, list/grid layouts, sort/service/view menus and the bottom add bar.

struct PlaylistView: View {
    let listID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var showShare = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showAddEntry = false
    @State private var showBulkAdd = false
    @State private var showMarvelSearch = false
    @State private var showDeleteConfirm = false

    private var list: Playlist { model.list(id: listID) ?? model.activeList }
    private var progress: ListProgress { list.progress }

    private var filterActive: Bool {
        !model.filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.filter.status != nil
    }

    private var entries: [Entry] {
        EntryFiltering.visible(list.entries, filter: model.filter, sort: model.prefs.sort)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: Metrics.gridMinimum), spacing: 12)]
    }

    private var searchBinding: Binding<String> {
        Binding(get: { model.filter.query }, set: { model.filter.query = $0 })
    }

    private var statusBinding: Binding<ReadStatus?> {
        Binding(get: { model.filter.status }, set: { model.filter.status = $0 })
    }

    var body: some View {
        List {
            Section {
                headerBlock
                statusFilter
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            entriesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: searchBinding, prompt: "Search this playlist")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showMarvelSearch) { MarvelSearchView(listID: listID) }
        .sheet(isPresented: $showAddEntry) { EntryFormView(listID: listID, entry: nil) }
        .sheet(isPresented: $showBulkAdd) { BulkAddView(listID: listID) }
        .sheet(isPresented: $showShare) { ShareView(list: list) }
        .alert("Rename playlist", isPresented: $showRename) {
            TextField("Playlist name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.renameList(id: listID, to: renameText) }
        }
        .confirmationDialog("Delete \(list.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete playlist", role: .destructive) { model.deleteList(id: listID) }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(progress.done) of \(progress.total) issues · \(progress.percent)%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressBar(fraction: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0,
                        tint: overallTint)
        }
        .padding(.vertical, 4)
    }

    private var overallTint: Color {
        guard progress.total > 0 else { return AppColor.status(.unread) }
        if progress.done >= progress.total { return AppColor.status(.finished) }
        if progress.done > 0 { return AppColor.status(.reading) }
        return AppColor.status(.unread)
    }

    private var statusFilter: some View {
        Picker("Status", selection: statusBinding) {
            Text("All").tag(ReadStatus?.none)
            Text("Not started").tag(ReadStatus?.some(.unread))
            Text("In progress").tag(ReadStatus?.some(.reading))
            Text("Finished").tag(ReadStatus?.some(.finished))
        }
        .pickerStyle(.segmented)
    }

    // MARK: Entries

    @ViewBuilder
    private var entriesSection: some View {
        if list.entries.isEmpty {
            EmptyPlaylistSection(showMarvelSearch: $showMarvelSearch, showAddEntry: $showAddEntry, showBulkAdd: $showBulkAdd)
        } else if entries.isEmpty {
            NoMatchesSection()
        } else {
            if !filterActive, let up = model.upNext {
                Section {
                    UpNextCard(entry: up.entry, issue: up.issue, listID: listID)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if model.prefs.view == .grid {
                Section {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(entries) { entry in
                            EntryCard(entry: entry, listID: listID)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry, listID: listID, index: model.showsReadingOrderNumbers ? index : nil)
                    }
                    .onMove { source, destination in
                        guard model.showsReadingOrderNumbers else { return }
                        model.moveEntries(from: source, to: destination, in: listID)
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                showMarvelSearch = true
            } label: {
                Text("Find on Marvel")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button("Add manually") { showAddEntry = true }
                Button("Bulk add") { showBulkAdd = true }
            } label: {
                Text("Add").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if model.prefs.view == .list && model.showsReadingOrderNumbers {
                EditButton()
            }
            Menu {
                Button("Share…") { showShare = true }
                Button("Rename…") {
                    renameText = list.name
                    showRename = true
                }

                Picker("Sort", selection: Binding(get: { model.prefs.sort }, set: { model.setSort($0) })) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Picker(
                    "Read on",
                    selection: Binding(get: { list.service }, set: { model.setListService(id: listID, service: $0) })
                ) {
                    ForEach(model.services) { service in
                        Text(service.name).tag(service.id)
                    }
                }

                Picker("View", selection: Binding(get: { model.prefs.view }, set: { model.setView($0) })) {
                    Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                    Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                }

                Divider()
                Button("Delete playlist", role: .destructive) { showDeleteConfirm = true }
                    .disabled(model.lists.count == 1)
            } label: {
                Label("Playlist menu", systemImage: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Up next card

private struct UpNextCard: View {
    let entry: Entry
    let issue: Issue
    let listID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var readURL: URL? {
        model.readURL(for: entry, issue: issue, in: model.list(id: listID))
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverThumb(entry: entry, width: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("Up next").font(.caption).foregroundStyle(.secondary)
                Text(entry.series).font(.headline)
                if !entry.title.isEmpty {
                    Text(entry.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(entry.isSingleBook ? "Whole book" : "#\(issue.label)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if let readURL { openURL(readURL) }
                } label: {
                    Text("Read").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(readURL == nil)

                Button {
                    _ = model.markNextIssue(entryID: entry.id, in: listID)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Mark next issue done")
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Empty states

private struct EmptyPlaylistSection: View {
    @Binding var showMarvelSearch: Bool
    @Binding var showAddEntry: Bool
    @Binding var showBulkAdd: Bool

    var body: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Nothing on this playlist yet")
                    .font(.headline)
                Text("Search Marvel for a run and it fills in the issues, links and year for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Find on Marvel") { showMarvelSearch = true }
                    .buttonStyle(.borderedProminent)

                HStack(spacing: 16) {
                    Button("Bulk add") { showBulkAdd = true }
                    Button("Add manually") { showAddEntry = true }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct NoMatchesSection: View {
    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No matches")
                    .font(.headline)
                Text("Nothing on this playlist matches your search or filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
