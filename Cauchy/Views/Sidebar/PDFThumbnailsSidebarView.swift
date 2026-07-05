import PDFKit
import SwiftUI

struct PDFThumbnailsSidebarView: View {
    let document: PDFDocument
    let currentPageIndex: Int
    var onSelectPage: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        if let page = document.page(at: index) {
                            PDFPageThumbnailView(
                                page: page,
                                pageNumber: index + 1,
                                isCurrentPage: index == currentPageIndex,
                                onSelect: { onSelectPage(index) }
                            )
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .sidebarScrollEdgeEffect()
            .sidebarScrollContentInsets()
            .onChange(of: currentPageIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentPageIndex, anchor: .center)
            }
        }
    }
}
