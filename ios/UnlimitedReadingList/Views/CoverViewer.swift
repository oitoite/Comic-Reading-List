import SwiftUI

// MARK: - CoverViewer
//
// Full-screen artwork viewer: pinch to zoom, drag while zoomed, double-tap to reset,
// tap the background (while unzoomed) or the close button to dismiss.

struct CoverViewer: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1 { dismiss() }
                }

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(title)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnifyGesture)
                        .simultaneousGesture(dragGesture)
                        .onTapGesture(count: 2) { resetZoom() }
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                default:
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .accessibilityLabel("Close")
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, min(lastScale * value.magnification, 5))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { resetZoom() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1 else { return }
                lastOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}
