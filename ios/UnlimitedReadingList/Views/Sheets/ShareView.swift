import SwiftUI
import UIKit
import ReadingListCore

// MARK: - ShareView
//
// Port of `shareDialog` / `refreshShareLink` / `copyShareLink`
// (assets/app.js ~1822-1855). Nothing is uploaded: the whole playlist is packed
// into the link's own hash.

struct ShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let list: Playlist

    @State private var includeProgress = false
    @State private var url: URL?
    @State private var buildError: String?

    init(list: Playlist) { self.list = list }

    private var charCount: Int { url?.absoluteString.count ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include which issues are ticked off", isOn: $includeProgress)
                } footer: {
                    Text("The whole playlist is packed into the link itself — nothing is uploaded anywhere. Anyone who opens it is offered a copy of their own.")
                }

                Section("Link") {
                    if let url {
                        Text(url.absoluteString)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Text("\(Plural.count(list.entries.count, "entry", "entries")) · \(Plural.count(list.progress.total, "issue")) · \(charCount) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if charCount > Limits.shareUrlWarning {
                            Text("Long links get truncated by some chat apps; a saved copy travels better")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if let buildError {
                        Text(buildError).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                }

                if let url {
                    Section {
                        Button {
                            copy(url)
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: url)
                    }
                }
            }
            .navigationTitle("Share this playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: includeProgress) {
                build()
            }
        }
    }

    private func build() {
        do {
            url = try model.shareURL(for: list, includeProgress: includeProgress)
            buildError = nil
        } catch {
            url = nil
            buildError = "Could not build a link for this playlist."
        }
    }

    private func copy(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        model.showToast("Link copied")
    }
}
