import SwiftUI
import ReadingListCore

// MARK: - PlaylistsSidebar
//
// The sidebar column of the split view: playlists with their issue progress, add /
// rename / delete / reorder, the backup nag, and the app-wide "⋯" menu.

struct PlaylistsSidebar: View {
    @Environment(AppModel.self) private var model

    @State private var showNewList = false
    @State private var newListName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""
    @State private var deleting: Playlist?
    @State private var showBackup = false
    @State private var showServices = false
    @State private var showAbout = false

    private var selection: Binding<String?> {
        Binding(get: { model.activeListID }, set: { if let id = $0 { model.activeListID = id } })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(model.lists) { list in
                    PlaylistRow(list: list)
                        .tag(list.id)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleting = list
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button {
                                renaming = list
                                renameText = list.name
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                deleting = list
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                .onMove { model.moveLists(from: $0, to: $1) }
            }

            if let note = model.backupNote {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                        Button("Save a copy") { showBackup = true }
                            .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("\(Plural.count(model.lists.count, "playlist")) · \(Plural.count(model.totalIssues, "issue"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newListName = ""
                    showNewList = true
                } label: {
                    Label("New playlist", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                moreMenu
            }
        }
        .alert("New playlist", isPresented: $showNewList) {
            TextField("Playlist name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { model.addList(name: newListName) }
        }
        .alert("Rename playlist", isPresented: renamingBinding) {
            TextField("Playlist name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let renaming { model.renameList(id: renaming.id, to: renameText) }
            }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "this playlist")?",
            isPresented: deletingBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { model.deleteList(id: deleting.id) }
            }
        }
        .sheet(isPresented: $showBackup) { BackupView() }
        .sheet(isPresented: $showServices) { ServicesView() }
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    private var moreMenu: some View {
        Menu {
            Button("Save a copy…") { showBackup = true }
            Button("Restore from a copy…") { showBackup = true }
            Button("Paste a share link…") { showBackup = true }
            Divider()
            Button("Services…") { showServices = true }
            Picker(
                "Appearance",
                selection: Binding(get: { model.prefs.theme }, set: { model.setTheme($0) })
            ) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            Divider()
            Button("About…") { showAbout = true }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

private extension Theme {
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - PlaylistRow

private struct PlaylistRow: View {
    let list: Playlist

    private var progress: ListProgress { list.progress }

    private var tint: Color {
        guard progress.total > 0 else { return AppColor.status(.unread) }
        if progress.done >= progress.total { return AppColor.status(.finished) }
        if progress.done > 0 { return AppColor.status(.reading) }
        return AppColor.status(.unread)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(list.name).font(.body)
            Text("\(progress.done) of \(progress.total) issues")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressBar(fraction: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0, tint: tint)
        }
        .padding(.vertical, 4)
    }
}
