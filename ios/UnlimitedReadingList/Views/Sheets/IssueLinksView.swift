import SwiftUI
import ReadingListCore

// MARK: - IssueLinksView
//
// Port of `linksDialog` / `openLinksDialog` / `saveLinksFromForm`
// (assets/app.js ~1708-1747): one URL field per issue, for services that address
// an issue by numeric id rather than by a search template.

struct IssueLinksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let listID: String
    private let entryID: String

    @State private var labels: [String] = []
    @State private var urls: [String] = []

    init(listID: String, entryID: String) {
        self.listID = listID
        self.entryID = entryID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Some services address individual issues by id rather than by name — a search template cannot produce those, so paste them here. Open the issue on the service, copy the address bar (e.g. https://www.marvel.com/comics/issue/25182/fantastic-four-1998-570) and drop it on the matching row. A blank row falls back to the entry's direct link, then to the service search. Links must start with http:// or https://.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(labels.indices, id: \.self) { idx in
                        row(idx)
                    }
                }
            }
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func row(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labels[idx].isEmpty ? "Whole book" : labels[idx])
                .font(.subheadline.weight(.medium))
            TextField("https://www.marvel.com/comics/issue/…", text: binding(idx))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if idx < urls.count, !urls[idx].isEmpty, !Sanitizer.isHTTP(urls[idx]) {
                Text("Needs http:// or https://").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func binding(_ idx: Int) -> Binding<String> {
        Binding(
            get: { idx < urls.count ? urls[idx] : "" },
            set: { newValue in if idx < urls.count { urls[idx] = newValue } }
        )
    }

    private func load() {
        guard let entry = model.entry(id: entryID, in: listID) else { return }
        labels = entry.issues.map { $0.label }
        urls = entry.issues.map { $0.url }
    }

    private func save() {
        model.setIssueURLs(entryID: entryID, urls: urls, in: listID)
        dismiss()
    }
}
