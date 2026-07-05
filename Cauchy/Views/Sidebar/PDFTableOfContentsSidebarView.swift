import PDFKit
import SwiftUI

struct PDFTableOfContentsSidebarView: View {
    let document: PDFDocument
    var onSelectDestination: (PDFDestination) -> Void

    var body: some View {
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            List {
                OutlineRows(outline: root, onSelectDestination: onSelectDestination)
            }
            .listStyle(.sidebar)
            .sidebarScrollEdgeEffect()
            .sidebarScrollContentInsets()
        } else {
            ContentUnavailableView(
                "No Table of Contents",
                systemImage: "list.bullet.rectangle",
                description: Text("This document does not include an outline.")
            )
        }
    }
}

private struct OutlineRows: View {
    let outline: PDFOutline
    var onSelectDestination: (PDFDestination) -> Void

    var body: some View {
        ForEach(0..<outline.numberOfChildren, id: \.self) { index in
            if let child = outline.child(at: index) {
                OutlineRow(outline: child, onSelectDestination: onSelectDestination)
            }
        }
    }
}

private struct OutlineRow: View {
    let outline: PDFOutline
    var onSelectDestination: (PDFDestination) -> Void

    var body: some View {
        if outline.numberOfChildren > 0 {
            DisclosureGroup {
                OutlineRows(outline: outline, onSelectDestination: onSelectDestination)
            } label: {
                outlineLabel
            }
        } else {
            outlineLabel
        }
    }

    @ViewBuilder
    private var outlineLabel: some View {
        Button {
            if let destination = outline.destination {
                onSelectDestination(destination)
            }
        } label: {
            Text(outline.label ?? "Untitled")
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(outline.destination == nil)
    }
}
