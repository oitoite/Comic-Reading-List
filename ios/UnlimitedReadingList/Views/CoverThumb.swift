import SwiftUI
import ReadingListCore

// MARK: - CoverThumb
//
// A cover image (or a colour-block placeholder keyed to the series name) at a fixed
// width, portrait aspect ratio. Used by rows, cards and the detail sheet alike.

struct CoverThumb: View {
    let entry: Entry
    var width: CGFloat = Metrics.rowCoverWidth

    private var coverURL: URL? {
        guard Sanitizer.isHTTP(entry.cover) else { return nil }
        return URL(string: entry.cover)
    }

    var body: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width / Metrics.coverAspect)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.coverRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            AppColor.series(entry.series)
            Text(SeriesInitials.of(entry.series))
                .font(.system(size: max(10, width * 0.28), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - ProgressBar

/// A thin capsule progress bar, tinted by whatever status colour the caller wants.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(tint).frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - StarsView

struct StarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(AppColor.yellow)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}
