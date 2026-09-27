import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ReadingListCore

// MARK: - BackupDocument
//
// A minimal `FileDocument` wrapper around the exported JSON, for `.fileExporter`.

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - BackupView
//
// Port of `backupPayload` / `saveCopy` / `importJson` (assets/app.js ~1965-2072):
// save a copy (share sheet or Files), restore from a file, or paste a share link.

struct BackupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var shareFileURL: URL?
    @State private var showShareSheet = false
    @State private var exportDocument: BackupDocument?
    @State private var showFileExporter = false
    @State private var showFileImporter = false
    @State private var pasteText = ""
    @State private var message: String?

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                if let note = model.backupNote {
                    Section {
                        Text(note).foregroundStyle(.orange)
                    }
                }
                saveSection
                restoreSection
                pasteSection
                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareFileURL {
                    ActivityShareSheet(items: [shareFileURL]) { completed in
                        // Only a share that actually finished counts as a backup.
                        if completed { model.markBackedUp() }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: defaultFilename
            ) { result in
                switch result {
                case .success: model.markBackedUp()
                case .failure(let error): message = "Could not save: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                handleImport(result)
            }
        }
    }

    // MARK: Sections

    private var defaultFilename: String {
        let name = model.exportFileName()
        return name.hasSuffix(".json") ? String(name.dropLast(5)) : name
    }

    private var saveSection: some View {
        Section {
            Text("Everything lives only on this device. Save a copy to Files, iCloud Drive or anywhere else so it survives a reinstall.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                prepareShareFile()
            } label: {
                Label("Save a copy", systemImage: "square.and.arrow.up")
            }

            Button {
                prepareExportDocument()
            } label: {
                Label("Save to Files…", systemImage: "folder")
            }

            if model.prefs.backedUpAt > 0 {
                Text("Last saved \(lastSavedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Save a copy")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                Label("Choose a file…", systemImage: "square.and.arrow.down")
            }
            Text("Adds the playlists in that file alongside your existing ones, rather than replacing them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Restore")
        }
    }

    private var pasteSection: some View {
        Section {
            TextField("https://…/#list=…", text: $pasteText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { pasteText = s }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                Spacer()
                Button("Add") {
                    model.handleIncoming(text: pasteText)
                    dismiss()
                }
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Paste a share link")
        }
    }

    private var lastSavedText: String {
        Timestamps.date(fromMillis: model.prefs.backedUpAt)
            .formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Actions

    private func prepareShareFile() {
        do {
            let data = try model.exportData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(model.exportFileName())
            try data.write(to: url, options: .atomic)
            shareFileURL = url
            showShareSheet = true
        } catch {
            message = "Could not prepare the file to share."
        }
    }

    private func prepareExportDocument() {
        do {
            let data = try model.exportData()
            exportDocument = BackupDocument(data: data)
            showFileExporter = true
        } catch {
            message = "Could not prepare the export."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "Could not read that file: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                _ = model.importBackup(data)
                message = nil
            } catch {
                message = "Could not read that file."
            }
        }
    }
}

// MARK: - ActivityShareSheet
//
// `ShareLink` cannot say whether the user finished sharing or cancelled, and "did you
// actually save a copy" is exactly what the backup reminder depends on. UIKit's
// activity controller reports completion, so the backup date is only set on success.

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
