import SwiftUI
import ReadingListCore

// MARK: - IssueTray
//
// The tray that opens under a row/card: one pill per issue (tap to toggle done), plus
// the per-entry actions. Port of the web app's `issueTray()` (assets/app.js).

struct IssueTray: View {
    let entry: Entry
    let listID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var showLinks = false
    @State private var showEdit = false
    @State private var showRemoveConfirm = false

    private var list: Playlist? { model.list(id: listID) }
    private var status: ReadStatus { entry.status }
    private var hasProgress: Bool { entry.doneCount > 0 }

    private var cycleLabel: String {
        switch status {
        case .unread: return "Start"
        case .reading: return "Finish"
        case .finished: return "Clear"
        }
    }

    private var readTitle: String {
        guard let issue = entry.nextIssue else { return "Read" }
        return entry.isSingleBook ? "Read" : "Read #\(issue.label)"
    }

    private var readURL: URL? {
        model.readURL(for: entry, issue: entry.nextIssue, in: list)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(Array(entry.issues.enumerated()), id: \.offset) { index, issue in
                    pill(issue, index)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        if let readURL { openURL(readURL) }
                    } label: {
                        Text(readTitle)
                    }
                    .disabled(readURL == nil)

                    Button(cycleLabel) {
                        model.cycleEntry(entryID: entry.id, in: listID)
                    }

                    if hasProgress {
                        Button("Clear") {
                            model.clearIssues(entryID: entry.id, in: listID)
                        }
                    }

                    Button("Links") { showLinks = true }
                    Button("Edit") { showEdit = true }
                    Button("Remove", role: .destructive) { showRemoveConfirm = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 2)
        .confirmationDialog("Remove this entry?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeEntry(id: entry.id, from: listID)
            }
        }
        .sheet(isPresented: $showLinks) {
            IssueLinksView(listID: listID, entryID: entry.id)
        }
        .sheet(isPresented: $showEdit) {
            EntryFormView(listID: listID, entry: entry)
        }
    }

    private func pill(_ issue: Issue, _ index: Int) -> some View {
        let label = issue.label.isEmpty ? "Whole book" : issue.label
        return Button {
            model.toggleIssue(entryID: entry.id, index: index, in: listID)
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.footnote.weight(.medium))
                if !issue.url.isEmpty {
                    Image(systemName: "link")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(issue.done ? AppColor.status(.finished) : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(issue.done ? Color.clear : Color.secondary.opacity(0.4))
            }
            .foregroundStyle(issue.done ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            (issue.label.isEmpty ? "Whole book" : "Issue \(issue.label)") + (issue.done ? ", read" : ", unread")
        )
    }
}

// MARK: - FlowLayout
//
// A minimal wrapping HStack built on the `Layout` protocol (iOS 16+), so pills wrap
// onto as many lines as the row needs instead of scrolling or clipping.

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + (totalHeight > 0 ? spacing : 0)
                widestRow = max(widestRow, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight + (totalHeight > 0 ? spacing : 0)
        widestRow = max(widestRow, rowWidth)

        let width = maxWidth.isFinite ? maxWidth : widestRow
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
