import SwiftUI
import ReadingListCore

// MARK: - EntryDetailView
//
// The "tap a cover for the details" sheet: everything a row has to truncate, plus a
// Marvel blurb fetched lazily for entries with a resolvable Marvel issue id.

struct EntryDetailView: View {
    let listID: String
    let entryID: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showCoverViewer = false
    @State private var showEdit = false
    @State private var showLinks = false
    @State private var showShare = false
    @State private var showRemoveConfirm = false
    @State private var blurb = ""

    private var entry: Entry? { model.entry(id: entryID, in: listID) }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    ScrollView {
                        detailContent(entry)
                    }
                    .safeAreaInset(edge: .bottom) { readButton(entry) }
                } else {
                    ContentUnavailableView("This entry was removed", systemImage: "questionmark.square.dashed")
                }
            }
            .navigationTitle(entry?.series ?? "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if entry != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit") { showEdit = true }
                            Button("Links") { showLinks = true }
                            Button("Share…") { showShare = true }
                            Divider()
                            Button("Remove", role: .destructive) { showRemoveConfirm = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .onChange(of: entry == nil, initial: true) { _, isNil in
            if isNil { dismiss() }
        }
        .sheet(isPresented: $showEdit) {
            if let entry { EntryFormView(listID: listID, entry: entry) }
        }
        .sheet(isPresented: $showLinks) {
            IssueLinksView(listID: listID, entryID: entryID)
        }
        .sheet(isPresented: $showShare) {
            if let list = model.list(id: listID) { ShareView(list: list) }
        }
        .confirmationDialog("Remove this entry?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.removeEntry(id: entryID, from: listID)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showCoverViewer) {
            if let entry, Sanitizer.isHTTP(entry.cover), let url = URL(string: entry.cover) {
                CoverViewer(url: url, title: entry.series)
            }
        }
        .task(id: entryID) {
            await loadBlurb()
        }
    }

    @ViewBuilder
    private func detailContent(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    if Sanitizer.isHTTP(entry.cover) { showCoverViewer = true }
                } label: {
                    CoverThumb(entry: entry, width: 120)
                }
                .buttonStyle(.plain)
                .disabled(!Sanitizer.isHTTP(entry.cover))

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.series).font(.title2.weight(.bold))
                    if !entry.title.isEmpty {
                        Text(entry.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(entry.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.status(entry.status))

                    HStack(spacing: 8) {
                        Text("\(entry.doneCount)/\(entry.issues.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        ProgressBar(fraction: entry.progressFraction, tint: AppColor.status(entry.status))
                    }

                    if entry.rating > 0 { StarsView(rating: entry.rating) }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                detailRow("Issues", entry.isSingleBook ? "Single book" : IssueSpec.summarize(entry.issues))
                detailRow("Writer", entry.writer)
                detailRow("Artist", entry.artist)
                detailRow("Publisher", entry.publisher)
                detailRow("Year", entry.year.map { String($0) } ?? "")
                detailRow("Read on", model.service(for: entry, in: model.list(id: listID)).name)
                detailRow("Added", entry.addedDate.formatted(date: .abbreviated, time: .omitted))
            }

            if !entry.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }

            if !entry.notes.isEmpty {
                Text(entry.notes).font(.body)
            }

            if !blurb.isEmpty {
                Text(blurb).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding()
        .padding(.bottom, 60)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(value).font(.body)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func readButton(_ entry: Entry) -> some View {
        let issue = entry.nextIssue
        let url = model.readURL(for: entry, issue: issue, in: model.list(id: listID))
        Button {
            if let url { openURL(url) }
        } label: {
            Text(entry.isSingleBook ? "Read" : "Read #\(issue?.label ?? "")")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(url == nil)
        .padding()
        .background(.bar)
    }

    private func loadBlurb() async {
        guard let entry else { return }
        let firstIssueURL = entry.issues.first?.url ?? ""
        let source = firstIssueURL.isEmpty ? entry.url : firstIssueURL
        guard let idString = MetadataHelpers.marvelIssueID(from: source), let id = Int(idString) else { return }
        if let detail = try? await model.metadata.issueDetail(id), !detail.description.isEmpty {
            blurb = detail.description
        }
    }
}
