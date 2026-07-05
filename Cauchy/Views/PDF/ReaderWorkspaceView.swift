import SwiftUI
import PDFKit

struct ReaderWorkspaceView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        Group {
            if let document = workspace.pdfDocument {
                HStack(spacing: 0) {
                    Spacer(minLength: 40)

                    PDFViewportView(
                        document: document,
                        viewportState: $workspace.viewportCoordinator.viewport,
                        role: .primary,
                        selectionModeActive: workspace.selectionModeActive,
                        pageLayoutMode: workspace.pdfPageLayoutMode,
                        onSelectionCompleted: { capture in
                            workspace.handleSelection(capture)
                        },
                        onViewportChanged: { state in
                            workspace.viewportCoordinator.handleViewportChange(state: state)
                            workspace.persistWorkspace()
                        },
                        onTextSelectionChanged: { context in
                            workspace.handleTextSelection(context)
                        },
                        onBlockDetected: { block in
                            workspace.handleDetectedBlock(block)
                        },
                        onHighlightSelected: { id in
                            workspace.selectHighlight(id: id)
                        },
                        referenceIndex: workspace.referenceIndex,
                        referenceIndexReady: !workspace.isIndexingReferences && workspace.referenceIndexError == nil,
                        applyTrigger: workspace.viewportCoordinator.applyTrigger
                    )
                    .frame(maxWidth: 900)
                    .frame(maxHeight: .infinity)

                    ContextPanelResizeHandle(
                        width: Binding(
                            get: { workspace.contextPanelWidth },
                            set: { workspace.contextPanelWidth = $0 }
                        )
                    )

                    ContextPanelView(workspace: workspace)
                        .frame(width: workspace.contextPanelWidth)
                        .frame(maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Open a PDF",
                        systemImage: "doc.richtext",
                        description: Text("Open a technical textbook or paper to begin reading.")
                    )
                    Button("Open Document") {
                        workspace.openDocument()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .sheet(isPresented: $workspace.showOCRResult) {
            if let result = workspace.ocrResult {
                OCRResultView(
                    result: result,
                    previewImage: workspace.ocrPreviewImage,
                    onCopy: { workspace.copyLatexToClipboard() }
                )
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .overlay {
            if workspace.isProcessingOCR {
                ProgressView("Running OCR…")
                    .padding(20)
                    .glassEffect(in: .rect(cornerRadius: 12))
            }
        }
        .overlay {
            regionActionOverlay
        }
    }

    @ViewBuilder
    private var regionActionOverlay: some View {
        if workspace.highlightStore.pendingRegionCapture != nil, workspace.selectionModeActive == false {
            VStack(spacing: 12) {
                Text("Region selected")
                    .font(.headline)
                HStack {
                    Button("OCR") {
                        if let capture = workspace.highlightStore.pendingRegionCapture {
                            Task { await workspace.runOCR(on: capture) }
                        }
                    }
                    .buttonStyle(.glass)

                    Button("Save as Highlight") {
                        Task { await workspace.saveRegionAsHighlight() }
                    }
                    .buttonStyle(.glassProminent)

                    Button("Cancel") {
                        workspace.highlightStore.pendingRegionCapture = nil
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 12))
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )
    }
}
