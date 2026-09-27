import SwiftUI
import ReadingListCore

// MARK: - AboutView
//
// A short about screen: what the app is, where the data lives, the web app it
// shares a format with, and credit for the third-party Marvel index.

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    init() {}

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Unlimited Reading List builds ordered reading playlists of comic runs and arcs, and tracks which issues you've read on Marvel Unlimited, DC Universe Infinite or anywhere else.")
                }

                Section("Your data") {
                    Text("Everything stays on this device — there is no account and no server. Save a copy now and then (Backup) so it survives a reinstall; share links pack a whole playlist into a URL with nothing uploaded.")
                }

                Section("Web app") {
                    Link(destination: ShareCodec.webAppURL) {
                        Label("Open the web version", systemImage: "safari")
                    }
                    Text("Backups and share links move between the app and the site.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Credits") {
                    Text("Find on Marvel uses a free third-party index of Marvel comics at marvel.emreparker.com — someone else's service, not Marvel's own API.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
