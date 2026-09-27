import SwiftUI
import ReadingListCore

// MARK: - RootView
//
// The app's top-level split view: playlists in the sidebar, the active playlist as
// detail. Collapses to a plain navigation stack on iPhone automatically. Also owns the
// toast overlay and the incoming-share sheet/alert.

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlaylistsSidebar()
        } detail: {
            NavigationStack {
                PlaylistView(listID: model.activeListID)
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: incomingShareBinding) {
            IncomingShareView()
        }
        .alert("Couldn't add that", isPresented: incomingErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.incomingError ?? "")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                model.saveNow()
            }
        }
    }

    private var incomingShareBinding: Binding<Bool> {
        Binding(get: { model.incomingShare != nil }, set: { isPresented in
            if !isPresented { model.dismissIncoming() }
        })
    }

    private var incomingErrorBinding: Binding<Bool> {
        Binding(get: { model.incomingError != nil }, set: { isPresented in
            if !isPresented { model.incomingError = nil }
        })
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .shadow(radius: 6, y: 2)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
        }
    }
}
