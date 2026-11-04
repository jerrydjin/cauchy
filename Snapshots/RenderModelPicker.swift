import AppKit
import Foundation
import SwiftUI

/// Renders the open model menu for every connector. Rows and the checked
/// default come from `AssistantConnector`, which is also what the composer
/// menu reads. Apple Intelligence has no vendor model, so its panel is the
/// single system-model row.
@main
enum RenderModelPicker {
    @MainActor
    static func main() {
        do {
            try render()
        } catch {
            fputs("snapshot failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func render() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Snapshots/out")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let connectors = AssistantConnector.all
        guard connectors.count == 7 else {
            throw SnapshotError("expected 7 connectors, found \(connectors.count)")
        }
        for connector in connectors {
            if connector.id != .onDevice {
                guard !connector.models.isEmpty, connector.defaultChoice.modelID != nil else {
                    throw SnapshotError("\(connector.name) has no default model")
                }
            }
            let view = SnapshotChrome(
                caption: "\(connector.name) model picker",
                content: OpenModelMenu(connector: connector)
            )
            let url = output.appendingPathComponent(filename(for: connector.id))
            try writePNG(view, to: url, minimumBytes: 2_000)
        }
    }

    private static func filename(for id: AssistantConnectorID) -> String {
        switch id {
        case .onDevice: "picker-apple-intelligence.png"
        case .claudeCode: "picker-claude-code.png"
        case .codex: "picker-codex.png"
        case .antigravity: "picker-antigravity.png"
        case .anthropicAPI: "picker-anthropic-api.png"
        case .openaiAPI: "picker-openai-api.png"
        case .gemini: "picker-gemini-api.png"
        }
    }
}

private struct OpenModelMenu: View {
    let connector: AssistantConnector

    private var chosenModelID: String? { connector.defaultChoice.modelID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(connector.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            if connector.models.isEmpty {
                menuRow(title: connector.noModelsNote ?? connector.name, checked: true)
            } else {
                ForEach(connector.models) { model in
                    menuRow(title: model.name, checked: model.id == chosenModelID)
                }
            }
        }
        .frame(width: 280)
        .padding(.bottom, 6)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func menuRow(title: String, checked: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(checked ? Color.accentColor : Color.clear)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(checked ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}

private struct SnapshotChrome<Content: View>: View {
    var caption: String
    var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding(28)
        .background(Color(white: 0.94))
    }
}

private struct SnapshotError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    guard png.count >= minimumBytes, rep.pixelsWide > 40, rep.pixelsHigh > 40 else {
        throw SnapshotError("PNG is \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))\n", stdout)
}
