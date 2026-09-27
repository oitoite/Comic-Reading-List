import SwiftUI
import ReadingListCore

// MARK: - ServicesView
//
// Port of `servicesDialog` / `openServicesDialog` / `saveServicesFromForm`
// (assets/app.js ~1776-1818). Service names are fixed; only the search template
// and the metadata API base are editable.

struct ServicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [String: String] = [:]
    @State private var metaApiText: String = ""

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                ForEach(model.services) { service in
                    serviceSection(service)
                }
                metadataSection
                Section {
                    Button("Reset to defaults", role: .destructive) { reset() }
                }
            }
            .navigationTitle("Services")
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

    private func serviceSection(_ service: Service) -> some View {
        Section {
            TextField("https://example.com/search?q={q}", text: templateBinding(service.id))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            let current = templates[service.id] ?? service.template
            if !current.isEmpty && !Sanitizer.isHTTP(current) {
                Text("Needs http:// or https://").font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text(service.name)
        } footer: {
            Text("{q} becomes the series and issue together; {series} and {issue} are available separately.")
        }
    }

    private var metadataSection: some View {
        Section {
            TextField(MetadataAPI.defaultBase.absoluteString, text: $metaApiText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Comic metadata API")
        } footer: {
            Text("Powers “Find on Marvel”. Leave blank to use marvel.emreparker.com, a free third-party index of Marvel comics — someone else's service, so point this at a replacement if it moves.")
        }
    }

    private func templateBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { templates[id] ?? "" },
            set: { templates[id] = $0 }
        )
    }

    private func load() {
        for s in model.services {
            templates[s.id] = s.template
        }
        metaApiText = model.prefs.metaApi
    }

    private func save() {
        let updated = model.services.map { s in
            Service(id: s.id, name: s.name, template: templates[s.id] ?? s.template)
        }
        model.updateServices(updated, metaApi: metaApiText)
        dismiss()
    }

    private func reset() {
        model.resetServices()
        load()
    }
}
