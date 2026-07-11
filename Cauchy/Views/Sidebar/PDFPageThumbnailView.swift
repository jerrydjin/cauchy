import PDFKit
import SwiftUI

struct PDFPageThumbnailView: View {
    let page: PDFPage
    let pageNumber: Int
    let isCurrentPage: Bool
    var maxWidth: CGFloat = 160
    let thumbnailCache: PageThumbnailCache
    var onSelect: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }
                }
                .frame(maxWidth: maxWidth)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isCurrentPage ? Color.accentColor : Color.clear, lineWidth: 2)
                }

                Text("\(pageNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrentPage ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .task(id: pageNumber) {
            let renderWidth = maxWidth * 2
            if let cached = thumbnailCache.image(pageIndex: pageNumber - 1, width: renderWidth) {
                thumbnail = cached
            } else if let rendered = PDFRegionRenderer.renderPageThumbnail(page: page, maxWidth: renderWidth) {
                thumbnailCache.store(rendered, pageIndex: pageNumber - 1, width: renderWidth)
                thumbnail = rendered
            }
        }
    }
}
