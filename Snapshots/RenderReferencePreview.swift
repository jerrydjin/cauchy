import AppKit
import Foundation
import SwiftMath
import SwiftUI

/// Same flag as `FindBarView`. ImageRenderer drops AppKit-backed math, so the
/// card draws SwiftMath into an image when this is set. Defined here because
/// the snapshot tool does not compile the find bar.
private struct RendersForSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rendersForSnapshot: Bool {
        get { self[RendersForSnapshotKey.self] }
        set { self[RendersForSnapshotKey.self] = newValue }
    }
}

/// Renders the RHS reference card for a synthetic Proposition 2.5.1 whose
/// stored body still has a JSON `\n` inside `$…$` and a name that repeats the
/// label. The card is the fixed presentation: `ReferencePreviewPresentation`,
/// `ReferencePreviewStatementColumn`, `ReadingBlockCard`, and
/// `MessageContentView`.
@main
enum RenderReferencePreview {
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
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)

        let root = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Snapshots/out")
        let fixtureURL = root.appendingPathComponent("Snapshots/Fixtures/synthetic-proposition-2-5-1.json")
        let fixture = try JSONDecoder().decode(PropositionFixture.self, from: Data(contentsOf: fixtureURL))
        guard fixture.kind == "proposition", fixture.number == "2.5.1", fixture.name == "Proposition 2.5.1" else {
            throw SnapshotError("fixture is no longer the duplicated Proposition 2.5.1 case")
        }
        let raw = fixture.formattedBody
        // The two characters `\` and `n`, inside the formula, are the failure
        // Jerry shot. A real newline here would mean the fixture was already
        // unescaped.
        guard raw.contains("\\n"), !raw.contains("\n"), raw.contains("a(t)}\\nMoreover") else {
            throw SnapshotError("fixture lost the JSON \\\\n inside the formula: \(raw)")
        }

        guard let kind = ReferenceKind(rawValue: fixture.kind) else {
            throw SnapshotError("unknown reference kind \(fixture.kind)")
        }
        let block = DocumentBlock(
            reference: DetectedReference(kind: kind, number: fixture.number),
            formattedBody: raw,
            pageIndex: fixture.pageIndex,
            name: fixture.name
        )
        let model = ReferencePreviewPresentation.model(for: block)
        guard model.heading == "Proposition 2.5.1", !model.heading.contains("(") else {
            throw SnapshotError("heading still repeats the label: \(model.heading)")
        }
        guard case .statement(let text) = model.body else {
            throw SnapshotError("expected a statement body")
        }
        guard text.contains("\n"), !text.contains("\\n"), !text.contains("`") else {
            throw SnapshotError("statement text was not unescaped: \(text)")
        }

        let parsed = MessageRenderCache.parsed(for: text)
        guard parsed.needsRichRendering else {
            throw SnapshotError("statement collapsed to plain text: \(text)")
        }
        let lines = parsed.blocks.map(describe)
        guard let moreover = lines.firstIndex(where: { $0.contains("Moreover") }),
              lines[..<moreover].contains(where: { $0.contains("path") }) else {
            throw SnapshotError("Moreover is not its own paragraph: \(lines)")
        }
        guard !parsed.blocks.contains(where: containsCode) else {
            throw SnapshotError("a code span survived into the card: \(lines)")
        }
        let math = parsed.blocks.flatMap(mathLatex)
        guard math.contains(where: { $0.contains("\\pi") }) else {
            throw SnapshotError("the exponential lost \\pi: \(math)")
        }
        guard !math.contains(where: { $0.contains("Moreover") || $0.contains("functions") }) else {
            throw SnapshotError("prose is still inside a formula: \(math)")
        }
        try assertTypeset(text, label: "Proposition 2.5.1")

        guard let probe = MathMetrics.snapshotImage(
            latex: "\\gamma",
            mode: .inline,
            fontSize: 15,
            textColor: .primary
        ) else {
            throw SnapshotError("SwiftMath asImage produced nothing for \\gamma")
        }
        let probeInk = try inkCount(in: probe)
        guard probeInk > 0 else {
            throw SnapshotError("SwiftMath TIFF for \\gamma has no dark pixels (size \(probe.size))")
        }

        let card = SnapshotChrome(
            caption: "Reference panel · Proposition 2.5.1",
            content: ReferencePanelSnapshot(heading: model.heading, statement: text)
        )
        .environment(\.rendersForSnapshot, true)
        .environment(\.colorScheme, .light)

        let url = output.appendingPathComponent("reference-preview-proposition-2-5-1.png")
        try writePNG(card, to: url, minimumBytes: 12_000)
        fputs("heading: \(model.heading)\n", stdout)
        fputs("statement:\n\(text)\n", stdout)
        try renderMathStatement(output: output)
    }

    /// Inline `\gamma`, a `\frac` beside an existing `$…$`, bold-wrapped
    /// `$\frac{1}{2}$`, and a display `\begin{align}` that SwiftMath rejects
    /// until the environment is rewritten. Before the fix each of those was
    /// painted as source text.
    @MainActor
    private static func renderMathStatement(output: URL) throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let fixtureURL = root.appendingPathComponent("Snapshots/Fixtures/synthetic-statement-math.json")
        let fixture = try JSONDecoder().decode(PropositionFixture.self, from: Data(contentsOf: fixtureURL))
        guard fixture.kind == "lemma", fixture.number == "4.2", fixture.name == "Winding" else {
            throw SnapshotError("math fixture is no longer Lemma 4.2 (Winding)")
        }
        let raw = fixture.formattedBody
        guard raw.contains("\\begin{align}"),
              raw.contains("\\frac"),
              raw.contains("\\gamma"),
              raw.contains("\\label"),
              raw.contains("**$\\frac{1}{2}$**"),
              raw.contains("\\n"),
              !raw.contains("\n") else {
            throw SnapshotError("math fixture no longer contains the raw-TeX fall-through: \(raw)")
        }

        guard let kind = ReferenceKind(rawValue: fixture.kind) else {
            throw SnapshotError("unknown reference kind \(fixture.kind)")
        }
        let block = DocumentBlock(
            reference: DetectedReference(kind: kind, number: fixture.number),
            formattedBody: raw,
            pageIndex: fixture.pageIndex,
            name: fixture.name
        )
        let model = ReferencePreviewPresentation.model(for: block)
        guard model.heading == "Lemma 4.2 (Winding)" else {
            throw SnapshotError("math fixture heading changed: \(model.heading)")
        }
        guard case .statement(let text) = model.body else {
            throw SnapshotError("expected a statement body")
        }
        guard text.contains("\n"), !text.contains("\\n"), text.contains("\\begin{align}"), text.contains("Moreover") else {
            throw SnapshotError("math fixture was not unescaped: \(text)")
        }
        let dump = ReferenceMathRendering.plainTextDump(of: text)
        guard dump.contains("Moreover"), dump.contains("closed curve"), dump.contains("residue") else {
            throw SnapshotError("math fixture prose disappeared:\n\(dump)")
        }
        let sources = ReferenceMathRendering.mathSources(of: text)
        guard sources.contains(where: { $0.contains("\\gamma") }),
              sources.contains(where: { $0.contains("\\begin{align}") && $0.contains("\\frac") }),
              sources.contains(where: { $0.contains("\\frac{1}{2}") }) else {
            throw SnapshotError("math fixture did not reach SwiftMath: \(sources)")
        }
        try assertTypeset(text, label: "Lemma 4.2")

        let card = SnapshotChrome(
            caption: "Reference panel · Lemma 4.2",
            content: ReferencePanelSnapshot(heading: model.heading, statement: text)
        )
        .environment(\.rendersForSnapshot, true)
        .environment(\.colorScheme, .light)
        try writePNG(
            card,
            to: output.appendingPathComponent("reference-preview-statement-math.png"),
            minimumBytes: 8_000
        )

        let hover = SnapshotChrome(
            caption: "Citation hover · same statement",
            content: ReferenceHoverLabel(text: text, width: 360)
        )
        .environment(\.rendersForSnapshot, true)
        .environment(\.colorScheme, .light)
        try writePNG(
            hover,
            to: output.appendingPathComponent("reference-hover-statement-math.png"),
            minimumBytes: 4_000,
            minimumHeight: 200
        )
        fputs("math statement dump:\n\(ReferenceMathRendering.plainTextDump(of: text))\n", stdout)
    }

    /// Visible `Text` runs must not contain raw TeX, and every math run must
    /// produce a SwiftMath bitmap. The PNG alone cannot tell a typeset glyph
    /// from the source characters.
    @MainActor
    private static func assertTypeset(_ text: String, label: String) throws {
        let dump = ReferenceMathRendering.plainTextDump(of: text)
        if dump.contains("$") || dump.contains("\\frac") || dump.contains("\\begin{") || dump.contains("\\") {
            throw SnapshotError("\(label) plain text still has raw TeX:\n\(dump)")
        }
        let sources = ReferenceMathRendering.mathSources(of: text)
        guard !sources.isEmpty else {
            throw SnapshotError("\(label) produced no math runs:\n\(text)")
        }
        for source in sources {
            guard let rendered = LaTeXValidator.renderableLatex(from: source) else {
                throw SnapshotError("\(label) math did not typeset:\n\(source)")
            }
            if containsRejectedAlign(rendered) || rendered.contains("\\label") {
                throw SnapshotError("\(label) repair left a command SwiftMath rejects:\n\(rendered)")
            }
            guard let image = MathMetrics.snapshotImage(
                latex: rendered,
                mode: rendered.contains("\\frac") || rendered.contains("\\begin") ? .display : .inline,
                fontSize: rendered.contains("\\frac") || rendered.contains("\\begin") ? 17 : 15,
                textColor: .primary
            ) else {
                throw SnapshotError("\(label) SwiftMath drew nothing for:\n\(rendered)")
            }
            let ink = try inkCount(in: image)
            guard ink > 0 else {
                throw SnapshotError("\(label) formula bitmap is blank:\n\(rendered)")
            }
        }
    }

    /// `\begin{aligned}` contains the characters `\begin{align}`. Reject only
    /// the environment SwiftMath 1.7.3 does not implement.
    private static func containsRejectedAlign(_ latex: String) -> Bool {
        var rest = latex[...]
        while let range = rest.range(of: "\\begin{") {
            let name = rest[range.upperBound...]
            if name.hasPrefix("align}") || name.hasPrefix("align*") {
                return true
            }
            rest = name
        }
        return false
    }

    private static func describe(_ block: MessageBlock) -> String {
        switch block {
        case .text(let value):
            return value
        case .displayMath(let latex):
            return latex
        case .inlineLine(let segments):
            return segments.map(describeSegment).joined()
        }
    }

    private static func describeSegment(_ segment: MessageSegment) -> String {
        switch segment {
        case .text(let value), .bold(let value), .italic(let value), .code(let value):
            return value
        case .inlineMath(let latex), .displayMath(let latex):
            return latex
        }
    }

    private static func containsCode(_ block: MessageBlock) -> Bool {
        guard case .inlineLine(let segments) = block else { return false }
        return segments.contains { segment in
            if case .code = segment { return true }
            return false
        }
    }

    private static func mathLatex(_ block: MessageBlock) -> [String] {
        switch block {
        case .displayMath(let latex):
            return [latex]
        case .inlineLine(let segments):
            return segments.compactMap { segment in
                switch segment {
                case .inlineMath(let latex), .displayMath(let latex):
                    return latex
                default:
                    return nil
                }
            }
        case .text:
            return []
        }
    }

    fileprivate static func inkCount(in image: NSImage) throws -> Int {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw SnapshotError("math image has no bitmap")
        }
        return inkCount(in: rep)
    }

    /// Fixed step, not `pixels / 32`. A taller card (display math under a short
    /// paragraph) was sampled on a coarser grid than the proposition card, so
    /// `colorAt` reported 14 dark hits and the write was rejected even though
    /// the bitmap held the heading, the prose, and the formula.
    fileprivate static func inkCount(in rep: NSBitmapImageRep) -> Int {
        let step = 4
        if let data = rep.bitmapData {
            let bytesPerPixel = max(rep.bitsPerPixel / 8, 1)
            guard bytesPerPixel >= 3 else { return inkCountByColor(in: rep, step: step) }
            let rowBytes = rep.bytesPerRow
            var ink = 0
            var y = 0
            while y < rep.pixelsHigh {
                var x = 0
                while x < rep.pixelsWide {
                    let offset = y * rowBytes + x * bytesPerPixel
                    let r = Int(data[offset])
                    let g = Int(data[offset + 1])
                    let b = Int(data[offset + 2])
                    let a = bytesPerPixel >= 4 ? Int(data[offset + 3]) : 255
                    if a > 30 && (r + g + b) / 3 < 210 {
                        ink += 1
                    }
                    x += step
                }
                y += step
            }
            return ink
        }
        return inkCountByColor(in: rep, step: step)
    }

    private static func inkCountByColor(in rep: NSBitmapImageRep, step: Int) -> Int {
        var ink = 0
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y) {
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    if color.alphaComponent > 0.2 && brightness < 0.82 {
                        ink += 1
                    }
                }
                x += step
            }
            y += step
        }
        return ink
    }
}

private struct PropositionFixture: Decodable {
    var kind: String
    var number: String
    var name: String
    var pageIndex: Int
    var formattedBody: String
}

/// The reference column at the panel width the reader uses (380pt), with
/// Source closed. ScrollView is omitted: ImageRenderer does not draw one.
private struct ReferencePanelSnapshot: View {
    var heading: String
    var statement: String

    var body: some View {
        VStack(spacing: 0) {
            ReferencePreviewStatementColumn(heading: heading, statement: statement)
            ReferencePreviewSourceDisclosure(isExpanded: .constant(false)) {
                EmptyView()
            }
        }
        .frame(width: 380, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            Rectangle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(28)
        .frame(width: 436, alignment: .leading)
        .background(Color(white: 0.94))
    }
}

private struct SnapshotError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int, minimumHeight: Int = 400) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(width: 436, height: nil)
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    let ink = RenderReferencePreview.inkCount(in: rep)
    guard png.count >= minimumBytes,
          rep.pixelsWide > 800, rep.pixelsWide < 1100,
          rep.pixelsHigh > minimumHeight,
          ink > 20 else {
        throw SnapshotError("PNG \(url.lastPathComponent) is \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh), ink samples \(ink)")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))\n", stdout)
}
