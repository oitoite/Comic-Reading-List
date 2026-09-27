import SwiftUI
import ReadingListCore

// MARK: - EntryFormView
//
// Add / edit a run or arc. Port of `entryDialog` (index.html) and
// `openEntryDialog` / `saveEntryFromForm` (assets/app.js ~1367-1440). Editing an
// existing entry keeps its id/addedAt and re-merges the issue list through
// `IssueSpec.mergeIssues` so ticks already made survive a re-typed range.

struct EntryFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let listID: String
    private let existing: Entry?

    @State private var series: String
    @State private var title: String
    @State private var issuesText: String
    @State private var started: Bool
    @State private var writer: String
    @State private var artist: String
    @State private var publisher: String
    @State private var yearText: String
    @State private var service: String
    @State private var url: String
    @State private var cover: String
    @State private var tagsText: String
    @State private var notes: String
    @State private var rating: Int

    init(listID: String, entry: Entry?) {
        self.listID = listID
        self.existing = entry
        _series = State(initialValue: entry?.series ?? "")
        _title = State(initialValue: entry?.title ?? "")
        _issuesText = State(initialValue: entry.map { IssueSpec.summarize($0.issues) } ?? "")
        _started = State(initialValue: entry?.started ?? false)
        _writer = State(initialValue: entry?.writer ?? "")
        _artist = State(initialValue: entry?.artist ?? "")
        _publisher = State(initialValue: entry?.publisher ?? "")
        _yearText = State(initialValue: entry?.year.map { String($0) } ?? "")
        _service = State(initialValue: entry?.service ?? "")
        _url = State(initialValue: entry?.url ?? "")
        _cover = State(initialValue: entry?.cover ?? "")
        _tagsText = State(initialValue: entry?.tags.joined(separator: ", ") ?? "")
        _notes = State(initialValue: entry?.notes ?? "")
        _rating = State(initialValue: entry?.rating ?? 0)
    }

    // MARK: Derived

    private var parsedIssues: IssueSpec.ParseResult { IssueSpec.parse(issuesText) }

    private var issuesCaption: String {
        if issuesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Single unnumbered book"
        }
        let parsed = parsedIssues
        let count = parsed.labels.isEmpty ? 1 : parsed.labels.count
        var text = Plural.count(count, "issue")
        if parsed.truncated { text += " · capped at \(Limits.maxIssues)" }
        return text
    }

    private var canSave: Bool {
        !series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                seriesSection
                issuesSection
                creatorsSection
                readOnSection
                linksSection
                tagsSection
                notesSection
                ratingSection
            }
            .navigationTitle(existing == nil ? "Add a run or arc" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: Sections

    private var seriesSection: some View {
        Section {
            TextField("Series (required)", text: $series)
            TextField("Arc title", text: $title)
        }
    }

    private var issuesSection: some View {
        Section {
            TextField("294-296, 300, Annual 1", text: $issuesText, axis: .vertical)
                .lineLimit(2...4)
            Text(issuesCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Mark as started, even with no issues ticked yet", isOn: $started)
        } header: {
            Text("Issues")
        } footer: {
            Text("Ranges and lists: 294-296, 300, Annual 1")
        }
    }

    private var creatorsSection: some View {
        Section("Creators") {
            TextField("Writer", text: $writer)
            TextField("Artist", text: $artist)
            TextField("Publisher", text: $publisher)
            TextField("Year", text: $yearText)
                .keyboardType(.numberPad)
        }
    }

    private var readOnSection: some View {
        Section("Read on") {
            Picker("Service", selection: $service) {
                Text("Playlist default").tag("")
                ForEach(model.services) { svc in
                    Text(svc.name).tag(svc.id)
                }
            }
        }
    }

    private var linksSection: some View {
        Section("Links") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Direct link URL", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !url.isEmpty && !Sanitizer.isHTTP(url) {
                    Text("Needs http:// or https://").font(.caption).foregroundStyle(.red)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Cover image URL", text: $cover)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !cover.isEmpty && !Sanitizer.isHTTP(cover) {
                    Text("Needs http:// or https://").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            TextField("Comma separated", text: $tagsText)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
        }
    }

    private var ratingSection: some View {
        Section("Rating") {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .foregroundStyle(i <= rating ? AppColor.yellow : Color.secondary)
                        .onTapGesture { rating = (rating == i) ? 0 : i }
                        .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                }
                if rating > 0 {
                    Spacer()
                    Button("Clear") { rating = 0 }
                        .font(.caption)
                }
            }
            .font(.title3)
            .imageScale(.large)
        }
    }

    // MARK: Save

    private func save() {
        let parsed = parsedIssues
        let labels = parsed.labels.isEmpty ? [""] : parsed.labels
        let issues = IssueSpec.mergeIssues(existing: existing?.issues ?? [], labels: labels)
        let tags = tagsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let year = Int(yearText.trimmingCharacters(in: .whitespaces))

        let entry = Entry(
            id: existing?.id ?? IDs.make(),
            series: series,
            title: title,
            issues: issues,
            started: started,
            writer: writer,
            artist: artist,
            publisher: publisher,
            year: year,
            service: service,
            url: url,
            cover: cover,
            tags: tags,
            notes: notes,
            rating: rating,
            addedAt: existing?.addedAt ?? Timestamps.now()
        )

        if existing != nil {
            model.updateEntry(entry, in: listID)
        } else {
            model.addEntry(entry, to: listID)
        }
        if parsed.truncated {
            model.showToast("Issue list capped at \(Limits.maxIssues).")
        }
        dismiss()
    }
}
