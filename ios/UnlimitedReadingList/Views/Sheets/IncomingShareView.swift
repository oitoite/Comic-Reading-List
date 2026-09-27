import SwiftUI
import ReadingListCore

// MARK: - IncomingShareView
//
// Port of `incomingDialog` / `handleIncomingHash` / `acceptIncoming`
// (assets/app.js ~1859-1889). `model.incomingShare` is set by
// `AppModel.handleIncoming` once a link decodes into a playlist.

struct IncomingShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init() {}

    private var list: Playlist? { model.incomingShare }

    var body: some View {
        NavigationStack {
            Form {
                if let list {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(list.name).font(.headline)
                            Text("\(Plural.count(list.entries.count, "entry", "entries")) · \(Plural.count(list.progress.total, "issue"))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Entries") {
                        ForEach(list.entries.prefix(5)) { entry in
                            Text(entry.displayName)
                        }
                        if list.entries.count > 5 {
                            Text("and \(list.entries.count - 5) more")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("You get your own copy. Editing it changes nothing for whoever sent it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing to add.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add this shared playlist?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        model.dismissIncoming()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add a copy") {
                        model.acceptIncoming()
                        dismiss()
                    }
                    .disabled(list == nil)
                }
            }
        }
    }
}
