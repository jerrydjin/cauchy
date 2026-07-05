import SwiftUI

struct OCRResultView: View {
    let result: OCRResult
    let previewImage: CGImage?
    var onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("OCR Result")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Copy LaTeX") {
                    onCopy()
                }
                .buttonStyle(.glassProminent)
            }

            Text("Assistive conversion — not full math OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let previewImage {
                Image(decorative: previewImage, scale: 2.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Group {
                Text("Raw Text")
                    .font(.headline)
                ScrollView {
                    Text(result.rawText)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 100)

                Text("LaTeX")
                    .font(.headline)
                ScrollView {
                    Text(result.latexSnippet)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 100)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
    }
}
