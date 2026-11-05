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
            for dark in [true, false] {
                let view = SnapshotChrome(
                    caption: "\(connector.name) model picker",
                    dark: dark,
                    content: OpenModelMenu(connector: connector, dark: dark)
                )
                let url = output.appendingPathComponent(filename(for: connector.id, dark: dark))
                try writePNG(view, to: url, minimumBytes: 2_000)
            }
        }
        try renderUnavailable(to: output.appendingPathComponent("jerry-151-picker-unavailable.png"))
    }

    @MainActor
    private static func renderUnavailable(to url: URL) throws {
        let antigravity = AssistantConnectorID.antigravity.connector
        let codex = AssistantConnectorID.codex.connector
        let claude = AssistantConnectorID.claudeCode.connector
        let signedOut = ConnectorStatus.resolved(
            access: antigravity.access,
            name: antigravity.name,
            readiness: .blocked(.notSignedIn(.antigravity))
        )
        let missing = ConnectorStatus.resolved(
            access: codex.access,
            name: codex.name,
            readiness: .blocked(.notInstalled(.codex))
        )
        let ready = ConnectorStatus.resolved(
            access: claude.access,
            name: claude.name,
            readiness: .ready
        )
        guard !signedOut.allowsSelection, signedOut.menuTitle(name: antigravity.name) == "Antigravity — Not signed in" else {
            throw SnapshotError("Antigravity probe failure is not a greyed row")
        }
        guard !missing.allowsSelection, missing.menuTitle(name: codex.name) == "Codex — Not installed" else {
            throw SnapshotError("Codex probe failure is not a greyed row")
        }
        guard ready.allowsSelection, ready.menuTitle(name: claude.name) == claude.name else {
            throw SnapshotError("a ready connector should show its name alone")
        }
        let checking = ConnectorStatus.resolved(
            access: antigravity.access,
            name: antigravity.name,
            readiness: .checking
        )
        guard checking.shortNote == nil, checking.hint == nil, checking.allowsSelection else {
            throw SnapshotError("checking still has a picker note")
        }
        let view = SnapshotChrome(
            caption: "Model picker · probe failed",
            dark: true,
            content: UnavailableModelMenu(
                rows: [
                    (ready.menuTitle(name: claude.name), true),
                    (missing.menuTitle(name: codex.name), false),
                    (signedOut.menuTitle(name: antigravity.name), false),
                    (AssistantConnectorID.gemini.connector.name, true),
                ]
            )
        )
        try writePNG(view, to: url, minimumBytes: 2_000)
    }

    private static func filename(for id: AssistantConnectorID, dark: Bool) -> String {
        let base: String
        switch id {
        case .onDevice: base = "picker-apple-intelligence"
        case .claudeCode: base = "picker-claude-code"
        case .codex: base = "picker-codex"
        case .antigravity: base = "picker-antigravity"
        case .anthropicAPI: base = "picker-anthropic-api"
        case .openaiAPI: base = "picker-openai-api"
        case .gemini: base = "picker-gemini-api"
        }
        return dark ? "\(base).png" : "\(base)-light.png"
    }
}

private struct OpenModelMenu: View {
    let connector: AssistantConnector
    var dark: Bool

    private var chosenModelID: String? { connector.defaultChoice.modelID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(connector.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(dark ? Color(white: 0.68) : Color.secondary)
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
        .background(dark ? Color(white: 0.17) : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 1)
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
                .foregroundStyle(dark ? Color(white: 0.96) : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(checked ? (dark ? Color(red: 0.16, green: 0.36, blue: 0.62) : Color.accentColor.opacity(0.16)) : Color.clear)
    }
}

private struct UnavailableModelMenu: View {
    var rows: [(String, Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.clear)
                        .frame(width: 14)
                    Text(row.0)
                        .font(.system(size: 13))
                        .foregroundStyle(row.1 ? Color(white: 0.96) : Color(white: 0.42))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 280)
        .padding(.vertical, 4)
        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SnapshotChrome<Content: View>: View {
    var caption: String
    var dark: Bool
    var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(dark ? Color(white: 0.68) : Color.secondary)
            content
        }
        .padding(28)
        .background(dark ? Color(white: 0.09) : Color(white: 0.94))
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
