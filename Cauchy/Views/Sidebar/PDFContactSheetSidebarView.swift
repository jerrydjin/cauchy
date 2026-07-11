import PDFKit
import SwiftUI

struct PDFContactSheetSidebarView: View {
    let document: PDFDocument
    let currentPageIndex: Int
    let thumbnailCache: PageThumbnailCache
    var onSelectPage: (Int) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    if let page = document.page(at: index) {
                        PDFPageThumbnailView(
                            page: page,
                            pageNumber: index + 1,
                            isCurrentPage: index == currentPageIndex,
                            maxWidth: 88,
                            thumbnailCache: thumbnailCache,
                            onSelect: { onSelectPage(index) }
                        )
                    }
                }
            }
            .padding(12)
        }
        .sidebarScrollEdgeEffect()
        .sidebarScrollContentInsets()
    }
}
