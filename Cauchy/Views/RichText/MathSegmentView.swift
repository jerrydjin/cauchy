import AppKit
import SwiftMath
import SwiftUI

struct MathSegmentView: View {
    enum Mode {
        case inline
        case display
    }

    let latex: String
    var mode: Mode = .inline
    var fontSize: CGFloat = 16
    var textColor: Color = .primary

    var body: some View {
        Group {
            if let rendered = LaTeXValidator.cachedRenderableLatex(from: latex) {
                if mode == .display {
                    // Long equations scroll sideways inside the bubble rather
                    // than drawing past its edge.
                    ScrollingMathLabel(latex: rendered, fontSize: fontSize, textColor: textColor)
                } else {
                    MathLabelRepresentable(
                        latex: rendered,
                        mode: mode,
                        fontSize: fontSize,
                        textColor: textColor
                    )
                    // Sit the formula on the surrounding text's baseline instead
                    // of its own top edge, which floats it above the line.
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        MathMetrics.baseline(latex: rendered, mode: mode, fontSize: fontSize)
                            ?? dimensions[.bottom]
                    }
                }
            } else {
                Text(fallbackText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.85))
                    .textSelection(.enabled)
                    .multilineTextAlignment(mode == .display ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: mode == .inline, vertical: true)
        .frame(maxWidth: mode == .display ? .infinity : nil, alignment: mode == .display ? .center : .leading)
    }

    private var fallbackText: String {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }
}

enum LaTeXValidator {
    private static let plainBarRegex = try! NSRegularExpression(pattern: #"(?<![\\|])\|([^|]+?)\|"#)
    private static let escapedBarRegex = try! NSRegularExpression(pattern: #"\\\|([^|]+?)\\\|"#)

    private static let commandAliases: [(String, String)] = [
        ("\\leqslant", "\\leq"),
        ("\\geqslant", "\\geq"),
        ("\\leqq", "\\leq"),
        ("\\geqq", "\\geq"),
        ("\\coloneqq", ":="),
        ("\\eqqcolon", "=:"),
        ("\\varepsilon", "\\epsilon"),
    ]

    /// SwiftMath implements a subset of LaTeX, so a single unsupported command
    /// fails the whole block and drops it to raw source. These have no
    /// implementation but do have a supported stand-in taking the same number
    /// of braced arguments, which makes them a safe token swap — no brace
    /// matching needed. Applied only as a fallback candidate: an approximation
    /// (a rule under the terms instead of a brace) beats showing LaTeX source,
    /// but the model's own markup wins whenever it parses.
    /// Verified against MTMathListBuilder; see the mapping notes per row.
    private static let unsupportedCommandFallbacks: [(String, String)] = [
        ("\\operatorname*", "\\mathrm"),  // near-exact: loses operator spacing
        ("\\operatorname", "\\mathrm"),
        ("\\underbrace", "\\underline"),  // approximation: rule, not a brace
        ("\\overbrace", "\\overline"),
        ("\\overrightarrow", "\\vec"),    // approximation: short arrow
        ("\\dfrac", "\\frac"),            // exact
        ("\\tfrac", "\\frac"),
        ("\\varnothing", "\\emptyset"),   // exact
        ("\\lVert", "\\|"),               // exact
        ("\\rVert", "\\|"),
        ("\\bmod", "\\mathrm{mod}"),
        ("\\implies", "\\Longrightarrow"),
        ("\\impliedby", "\\Longleftarrow"),
    ]

    /// Delimiter-size hints SwiftMath lacks. Dropping them leaves the plain
    /// delimiter, which parses and renders at natural size.
    private static let droppedCommands = [
        "\\biggl", "\\biggr", "\\bigl", "\\bigr", "\\Biggl", "\\Biggr", "\\Bigl", "\\Bigr",
        "\\bigg", "\\Bigg", "\\big", "\\Big",
    ]

    static func sanitize(_ latex: String) -> String {
        var value = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: " \\,", with: " ")
        value = value.replacingOccurrences(of: "\\,", with: " ")

        for (unsupported, supported) in commandAliases {
            value = value.replacingOccurrences(of: unsupported, with: supported)
        }

        return value
    }

    /// Swaps commands SwiftMath does not implement for supported stand-ins.
    /// The trailing `(?![a-zA-Z])` stops a command from matching inside a
    /// longer one (`\big` must not rewrite `\bigcap`).
    static func substitutingUnsupportedCommands(_ latex: String) -> String {
        var value = latex
        for (unsupported, supported) in unsupportedCommandFallbacks where value.contains(unsupported) {
            value = replacingCommand(unsupported, with: supported, in: value)
        }
        for command in droppedCommands where value.contains(command) {
            value = replacingCommand(command, with: "", in: value)
        }
        return value
    }

    private static func replacingCommand(_ command: String, with replacement: String, in value: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: command) + "(?![a-zA-Z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    static func renderableLatex(from latex: String) -> String? {
        let base = sanitize(latex)
        // The model's own markup is tried first; the substituted forms are a
        // last resort before falling back to showing raw LaTeX source.
        let substituted = substitutingUnsupportedCommands(base)
        let candidates = uniqueCandidates([
            base,
            normalizePlainBars(base),
            normalizeEscapedBars(base),
            substituted,
            normalizePlainBars(substituted),
            normalizeEscapedBars(substituted),
        ])

        for candidate in candidates where buildsSuccessfully(candidate) {
            return candidate
        }
        return nil
    }

    // MARK: Main-actor render memo

    // renderableLatex compiles up to three SwiftMath candidates, and
    // MathSegmentView calls it from body on every re-render. Failures are the
    // most expensive outcome (all three candidates compile), so they are
    // cached too. renderableLatex itself stays nonisolated for the reference
    // index builder, which validates LaTeX off the main actor.
    @MainActor private static var renderableCache: [String: String?] = [:]
    @MainActor private static var renderableCacheOrder: [String] = []
    private static let renderableCacheCapacity = 256

    @MainActor
    static func cachedRenderableLatex(from latex: String) -> String? {
        if let hit = renderableCache[latex] {
            return hit
        }
        let rendered = renderableLatex(from: latex)
        renderableCache[latex] = rendered
        renderableCacheOrder.append(latex)
        if renderableCacheOrder.count > renderableCacheCapacity {
            renderableCache.removeValue(forKey: renderableCacheOrder.removeFirst())
        }
        return rendered
    }

    static func isValid(_ latex: String) -> Bool {
        renderableLatex(from: latex) != nil
    }

    private static func uniqueCandidates(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func buildsSuccessfully(_ latex: String) -> Bool {
        guard !latex.isEmpty else { return false }
        var error: NSError?
        _ = MTMathListBuilder.build(fromString: latex, error: &error)
        return error == nil
    }

    private static func normalizePlainBars(_ latex: String) -> String {
        guard latex.contains("|"), !latex.contains("\\left") else { return latex }
        return wrappingBarMatches(in: latex, regex: plainBarRegex)
    }

    private static func normalizeEscapedBars(_ latex: String) -> String {
        guard latex.contains("\\|") else { return latex }
        return wrappingBarMatches(in: latex, regex: escapedBarRegex)
    }

    private static func wrappingBarMatches(in latex: String, regex: NSRegularExpression) -> String {
        let nsRange = NSRange(latex.startIndex..., in: latex)
        let matches = regex.matches(in: latex, range: nsRange).reversed()
        var output = latex
        for match in matches {
            guard let fullRange = Range(match.range, in: output),
                  let innerRange = Range(match.range(at: 1), in: output) else { continue }
            let inner = output[innerRange].trimmingCharacters(in: .whitespaces)
            output.replaceSubrange(fullRange, with: "\\left| \(inner) \\right|")
        }
        return output
    }
}

/// Measures typeset formulas without going through a live view, so both the
/// SwiftUI size and the baseline come from the same numbers the renderer uses.
@MainActor
enum MathMetrics {
    struct Measurement {
        /// Includes `contentInsets`, matching what the label reports.
        let size: CGSize
        /// Distance from the top edge down to the formula's baseline.
        let baseline: CGFloat
    }

    static let contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

    /// How far a formula may be shrunk to fit its container before it is
    /// allowed to overflow (and, for display math, scroll) instead. Shrinking
    /// without a floor turns long equations into unreadable specks.
    static let minimumScale: CGFloat = 0.72
    static let minimumFontSize: CGFloat = 11

    private static let measuringLabel = MTMathUILabel()
    private static var cache: [String: Measurement] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheCapacity = 512

    static func measure(latex: String, mode: MathSegmentView.Mode, fontSize: CGFloat) -> Measurement? {
        let key = "\(mode)|\(Int(fontSize.rounded() * 100))|\(latex)"
        if let hit = cache[key] { return hit }

        let label = measuringLabel
        configureMathLabel(label, latex: latex, mode: mode, fontSize: fontSize, textColor: .primary)
        let size = label.fittingSize
        label.frame = CGRect(origin: .zero, size: size)
        label.layout()
        guard let display = label.displayList, size.width > 0, size.height > 0 else { return nil }

        // The label floors the vertical centring at half the font size, which
        // nudges the baseline down for short formulas; mirror that here so the
        // guide matches what is drawn.
        let content = display.ascent + display.descent
        let centred = max(content, fontSize / 2)
        let baseline = display.ascent + contentInsets.top - (content - centred) / 2

        let measurement = Measurement(size: size, baseline: baseline)
        cache[key] = measurement
        cacheOrder.append(key)
        if cacheOrder.count > cacheCapacity {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        return measurement
    }

    static func baseline(latex: String, mode: MathSegmentView.Mode, fontSize: CGFloat) -> CGFloat? {
        measure(latex: latex, mode: mode, fontSize: fontSize)?.baseline
    }

    /// Largest font size no bigger than `fontSize` that fits `maxWidth`, down to
    /// the floor. Typeset widths do not scale linearly with the font size, so
    /// this closes in over a few passes rather than assuming one ratio.
    static func fittedFontSize(
        latex: String,
        mode: MathSegmentView.Mode,
        fontSize: CGFloat,
        maxWidth: CGFloat?
    ) -> CGFloat {
        guard let maxWidth, maxWidth.isFinite, maxWidth > 0 else { return fontSize }
        let floorSize = max(minimumFontSize, fontSize * minimumScale)
        var candidate = fontSize

        for _ in 0..<4 {
            guard let width = measure(latex: latex, mode: mode, fontSize: candidate)?.size.width,
                  width > maxWidth else {
                return candidate
            }
            let next = max(floorSize, candidate * (maxWidth / width))
            if next >= candidate { return floorSize }
            candidate = next
        }
        return candidate
    }
}

@MainActor
private func configureMathLabel(
    _ label: MTMathUILabel,
    latex: String,
    mode: MathSegmentView.Mode,
    fontSize: CGFloat,
    textColor: Color
) {
    label.displayErrorInline = false
    label.labelMode = mode == .inline ? .text : .display
    label.textAlignment = .left
    label.contentInsets = MathMetrics.contentInsets
    label.fontSize = fontSize
    label.textColor = NSColor(textColor)
    label.latex = latex
}

/// Inline math: sized to the formula itself and shrunk a little when it would
/// not otherwise fit the line.
private struct MathLabelRepresentable: NSViewRepresentable {
    let latex: String
    let mode: MathSegmentView.Mode
    let fontSize: CGFloat
    let textColor: Color

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        configureMathLabel(label, latex: latex, mode: mode, fontSize: fontSize, textColor: textColor)
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        configureMathLabel(
            label,
            latex: latex,
            mode: mode,
            fontSize: fittedFontSize(for: label.frame.width > 0 ? label.frame.width : nil),
            textColor: textColor
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        let fitted = fittedFontSize(for: proposal.width)
        configureMathLabel(nsView, latex: latex, mode: mode, fontSize: fitted, textColor: textColor)
        return MathMetrics.measure(latex: latex, mode: mode, fontSize: fitted)?.size
    }

    private func fittedFontSize(for width: CGFloat?) -> CGFloat {
        MathMetrics.fittedFontSize(latex: latex, mode: mode, fontSize: fontSize, maxWidth: width)
    }
}

/// Display math: shrinks to fit the bubble, and once it hits the floor the
/// remainder scrolls sideways instead of drawing over everything around it.
private struct ScrollingMathLabel: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let textColor: Color

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = MTMathUILabel()
        scrollView.drawsBackground = false
        // No scroller at all: an equation is only a couple of lines tall, so
        // even an overlay scroller lands on top of the formula it belongs to.
        // Trackpad and wheel scrolling still work without it.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let label = scrollView.documentView as? MTMathUILabel else { return }
        let fitted = MathMetrics.fittedFontSize(
            latex: latex,
            mode: .display,
            fontSize: fontSize,
            maxWidth: scrollView.contentSize.width > 0 ? scrollView.contentSize.width : nil
        )
        configureMathLabel(label, latex: latex, mode: .display, fontSize: fitted, textColor: textColor)
        if let size = MathMetrics.measure(latex: latex, mode: .display, fontSize: fitted)?.size {
            // A formula narrower than the viewport fills it so the label's own
            // left alignment still lands where the parent centres the view.
            label.frame = CGRect(
                origin: .zero,
                size: CGSize(width: max(size.width, scrollView.contentSize.width), height: size.height)
            )
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let fitted = MathMetrics.fittedFontSize(
            latex: latex,
            mode: .display,
            fontSize: fontSize,
            maxWidth: proposal.width
        )
        guard let size = MathMetrics.measure(latex: latex, mode: .display, fontSize: fitted)?.size else {
            return nil
        }
        guard let width = proposal.width, width.isFinite, width > 0 else { return size }
        // Never claim more width than the container gave us: overshoot here is
        // exactly what used to spill past the bubble.
        return CGSize(width: min(size.width, width), height: size.height)
    }
}
