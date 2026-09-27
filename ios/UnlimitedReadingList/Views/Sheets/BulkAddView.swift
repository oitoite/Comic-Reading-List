import SwiftUI
import UIKit
import ReadingListCore

// MARK: - BulkAddView
//
// Port of `bulkDialog` / `updateBulkPreview` / `addBulkFromForm`
// (assets/app.js ~1751-1772): paste a whole reading order, one entry per line.

struct BulkAddView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let listID: String
    @State private var text = ""

    init(listID: String) { self.listID = listID }

    private var result: BulkParser.Result { BulkParser.parse(text) }

    private var previewText: String {
        var bits: [String] = []
        if result.entries.isEmpty {
            bits.append("Nothing to add yet")
        } else {
            bits.append("\(Plural.count(result.entries.count, "entry", "entries")) · \(Plural.count(result.issueCount, "issue"))")
        }
        if result.skipped > 0 { bits.append("\(Plural.count(result.skipped, "line")) skipped") }
        if result.truncated { bits.append("capped") }
        return bits.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("One per line: Series #issues | Optional arc title")
                    Text("A line with no # becomes a single unnumbered book.")
                } header: {
                    Text("Reading order")
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("Example:\nThe Amazing Spider-Man #294-296 | Kraven's Last Hunt\nWeb of Spider-Man #31-32\nWatchmen")
                }

                Section {
                    Text(previewText)
                        .foregroundStyle(result.entries.isEmpty ? .secondary : .primary)
                }
            }
            .navigationTitle("Bulk add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(Plural.count(result.entries.count, "entry", "entries"))") { addAll() }
                        .disabled(result.entries.isEmpty)
                }
            }
        }
    }

    private func addAll() {
        let res = result
        guard !res.entries.isEmpty else { return }
        model.addEntries(res.entries, to: listID)
        dismiss()
    }

    private func pasteFromClipboard() {
        if let s = UIPasteboard.general.string {
            text = s
        }
    }
}
