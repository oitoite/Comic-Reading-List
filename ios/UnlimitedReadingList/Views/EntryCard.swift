import SwiftUI
import ReadingListCore

// MARK: - EntryCard
//
// Cover-forward tile for grid view: cover with a status-tinted progress bar along the
// bottom and a "3/5" badge, series + arc underneath. Tapping the tile opens the detail
// sheet; the context menu mirrors EntryRow's.

struct EntryCard: View {
    let entry: Entry
    let listID: String

    @Environment(AppModel.self) private var model

    @State private var showDetail = false
    @State private var showEdit = false
    @State private var showLinks = false
    @State private var showShare = false
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            Text(entry.series)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
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

    private var cover: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                CoverThumb(entry: entry, width: geo.size.width)
                ProgressBar(fraction: entry.progressFraction, tint: AppColor.status(entry.status))
                    .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(entry.doneCount)/\(entry.issues.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(6)
            }
        }
        .aspectRatio(Metrics.coverAspect, contentMode: .fit)
    }
}
