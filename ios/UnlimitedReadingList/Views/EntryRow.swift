import SwiftUI
import ReadingListCore

// MARK: - EntryRow
//
// One playlist entry in list view: optional reading-order number, cover, series/arc/
// meta, issue progress. Tapping the row body expands the issue tray below it; tapping
// the cover opens the detail sheet instead.

struct EntryRow: View {
    let entry: Entry
    let listID: String
    let index: Int?

    @Environment(AppModel.self) private var model

    @State private var showDetail = false
    @State private var showEdit = false
    @State private var showLinks = false
    @State private var showShare = false
    @State private var showRemoveConfirm = false

    private var isExpanded: Bool { model.expandedEntryIDs.contains(entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                if let index, model.showsReadingOrderNumbers {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .padding(.top, 4)
                }

                CoverThumb(entry: entry, width: Metrics.rowCoverWidth)
                    .onTapGesture { showDetail = true }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.series).font(.headline)
                    if !entry.title.isEmpty {
                        Text(entry.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !metaLine.isEmpty {
                        Text(metaLine).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("\(entry.doneCount)/\(entry.issues.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        ProgressBar(fraction: entry.progressFraction, tint: AppColor.status(entry.status))
                    }
                    .padding(.top, 2)
                    if entry.rating > 0 {
                        StarsView(rating: entry.rating)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleExpanded(entry.id) }

            if isExpanded {
                IssueTray(entry: entry, listID: listID)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .padding(.leading, index != nil && model.showsReadingOrderNumbers ? 30 : 0)
            }
        }
        .animation(.default, value: isExpanded)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .swipeActions(edge: .leading) {
            Button {
                _ = model.markNextIssue(entryID: entry.id, in: listID)
            } label: {
                Label("Read next", systemImage: "checkmark.circle")
            }
            .tint(AppColor.status(.reading))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                showEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                _ = model.markNextIssue(entryID: entry.id, in: listID)
            } label: { Label("Read next", systemImage: "checkmark.circle") }
            Button {
                model.markAllIssues(entryID: entry.id, in: listID)
            } label: { Label("Finish", systemImage: "checkmark.circle.fill") }
            Button {
                model.clearIssues(entryID: entry.id, in: listID)
            } label: { Label("Clear", systemImage: "arrow.counterclockwise") }
            Divider()
            Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
            Button { showLinks = true } label: { Label("Links", systemImage: "link") }
            Button { showShare = true } label: { Label("Share…", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive) { showRemoveConfirm = true } label: { Label("Remove", systemImage: "trash") }
        }
        .confirmationDialog("Remove this entry?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeEntry(id: entry.id, from: listID)
            }
        }
        .sheet(isPresented: $showDetail) {
            EntryDetailView(listID: listID, entryID: entry.id)
        }
        .sheet(isPresented: $showEdit) {
            EntryFormView(listID: listID, entry: entry)
        }
        .sheet(isPresented: $showLinks) {
            IssueLinksView(listID: listID, entryID: entry.id)
        }
        .sheet(isPresented: $showShare) {
            if let list = model.list(id: listID) {
                ShareView(list: list)
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        let creators = [entry.writer, entry.artist].filter { !$0.isEmpty }.joined(separator: " / ")
        if !creators.isEmpty { parts.append(creators) }

        var pub: [String] = []
        if !entry.publisher.isEmpty { pub.append(entry.publisher) }
        if let year = entry.year { pub.append(String(year)) }
        if !pub.isEmpty { parts.append(pub.joined(separator: " · ")) }

        let serviceName = model.service(for: entry, in: model.list(id: listID)).name
        if !serviceName.isEmpty { parts.append(serviceName) }

        return parts.joined(separator: " · ")
    }
}
