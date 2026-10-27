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
    /// Failed math in chat stays a monospace chip. The reference card passes
    /// the body font so a broken span cannot change typeface mid-sentence.
    var fallbackFont: Font = .system(.callout, design: .monospaced)

    /// ImageRenderer does not paint `NSViewRepresentable`. The designer
    /// snapshot sets this and we draw the same SwiftMath display list into
    /// an image instead. The reader still uses the live label.
    @Environment(\.rendersForSnapshot) private var rendersForSnapshot

    var body: some View {
        Group {
            if rendersForSnapshot, let rendered = LaTeXValidator.cachedRenderableLatex(from: latex) {
                if let image = MathMetrics.snapshotImage(
                    latex: rendered,
                    mode: mode,
                    fontSize: fontSize,
                    textColor: textColor
                ) {
                    Image(nsImage: image)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            MathMetrics.baseline(latex: rendered, mode: mode, fontSize: fontSize)
                                ?? dimensions[.bottom]
                        }
                } else {
                    Text(visibleFallback)
                        .font(fallbackFont)
                        .foregroundStyle(textColor.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let rendered = LaTeXValidator.cachedRenderableLatex(from: latex) {
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
                // SwiftMath rejected every repair. The source string is the
                // accessibility label; painting it here is how `\frac` and
                // `\begin{align}` showed up as raw TeX.
                Text(visibleFallback)
                    .font(fallbackFont)
                    .foregroundStyle(textColor.opacity(0.85))
                    .textSelection(.enabled)
                    .multilineTextAlignment(mode == .display ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: mode == .inline, vertical: true)
        .frame(maxWidth: mode == .display ? .infinity : nil, alignment: mode == .display ? .center : .leading)
        // SwiftMath draws the formula without exposing its text to assistive
        // technology. Preserve the original expression, including commands
        // approximated for rendering, instead of leaving a silent gap.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Math expression: \(sourceText)")
        .accessibilityAddTraits(.isStaticText)
    }

    /// Spoken form. VoiceOver gets the formula even when the glyphs are a bitmap.
    private var sourceText: String {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }

    /// Drawn only when nothing buildable remains. Never the raw source: a
    /// backslash or a dollar in this string is the fall-through the card,
    /// the hover, and Source used to show.
    private var visibleFallback: String {
        if sourceText.contains("\\") || sourceText.contains("$") { return "…" }
        return sourceText
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
        ("\\boldsymbol", "\\mathbf"),
        ("\\pmb", "\\mathbf"),
    ]

    /// Delimiter-size hints SwiftMath lacks. Dropping them leaves the plain
    /// delimiter, which parses and renders at natural size.
    private static let droppedCommands = [
        "\\biggl", "\\biggr", "\\bigl", "\\bigr", "\\Biggl", "\\Biggr", "\\Bigl", "\\Bigr",
        "\\bigg", "\\Bigg", "\\big", "\\Big",
        "\\substack", "\\middle",
        "\\notag", "\\nonumber", "\\qedhere", "\\allowdisplaybreaks",
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
        // The model's own markup is tried first. Substitutions and environment
        // rewrites are what keep one unknown command (`\label`, `\begin{align}`)
        // from dropping the whole formula to raw source.
        let prepared = prepareForTypesetting(base)
        let substituted = substitutingUnsupportedCommands(prepared)
        let candidates = uniqueCandidates([
            base,
            normalizePlainBars(base),
            normalizeEscapedBars(base),
            prepared,
            normalizePlainBars(prepared),
            normalizeEscapedBars(prepared),
            substituted,
            normalizePlainBars(substituted),
            normalizeEscapedBars(substituted),
        ])

        for candidate in candidates where buildsSuccessfully(candidate) {
            return candidate
        }
        return repairUntilBuildable(substituted)
    }

    /// Rewrites the environments and decorations SwiftMath 1.7.3 rejects.
    /// `\begin{align}` is "Unknown environment"; `\begin{align*}` fails earlier
    /// because the `*` is not part of the environment name the parser reads.
    private static func prepareForTypesetting(_ latex: String) -> String {
        rewriteEnvironments(stripDecorations(latex))
    }

    private static let decorationsWithArgument = [
        "label", "tag", "eqref", "ref", "cite", "footnote", "marginpar",
    ]

    private static let decorationsWithoutArgument = [
        "notag", "nonumber", "qedhere", "allowdisplaybreaks",
    ]

    /// `align` with an alignment tab becomes `aligned` (SwiftMath knows that
    /// name). A one-column `equation` / `align` is unwrapped. The star in
    /// `align*` is removed as part of the rename.
    private static let environmentTargets: [(String, String)] = [
        ("align*", "aligned"),
        ("flalign*", "aligned"),
        ("flalign", "aligned"),
        ("alignat*", "aligned"),
        ("alignat", "aligned"),
        ("align", "aligned"),
        ("eqnarray*", "eqnarray"),
        ("gather*", "gather"),
        ("gathered", "gather"),
        ("multline*", "gather"),
        ("multline", "gather"),
        ("equation*", ""),
        ("equation", ""),
        ("displaymath", ""),
        ("math", ""),
    ]

    private static func stripDecorations(_ latex: String) -> String {
        var output = ""
        var index = latex.startIndex
        while index < latex.endIndex {
            guard latex[index] == "\\",
                  let commandEnd = endOfCommandName(in: latex, from: index) else {
                output.append(latex[index])
                index = latex.index(after: index)
                continue
            }
            var name = String(latex[latex.index(after: index)..<commandEnd])
            var cursor = commandEnd
            if cursor < latex.endIndex, latex[cursor] == "*" {
                name.append("*")
                cursor = latex.index(after: cursor)
            }
            let baseName = name.hasSuffix("*") ? String(name.dropLast()) : name
            if decorationsWithArgument.contains(baseName) {
                let afterSpace = skipSpaces(in: latex, from: cursor)
                if afterSpace < latex.endIndex, latex[afterSpace] == "{" {
                    let innerStart = latex.index(after: afterSpace)
                    let end = endOfBraceGroup(in: latex, open: afterSpace)
                    let innerEnd = end > innerStart ? latex.index(before: end) : innerStart
                    if (baseName == "eqref" || baseName == "ref"), innerStart < innerEnd {
                        output.append("(")
                        output.append(contentsOf: latex[innerStart..<innerEnd])
                        output.append(")")
                    }
                    index = end
                } else {
                    index = cursor
                }
                continue
            }
            if decorationsWithoutArgument.contains(baseName) {
                index = cursor
                continue
            }
            if baseName == "ensuremath" {
                let afterSpace = skipSpaces(in: latex, from: cursor)
                if afterSpace < latex.endIndex, latex[afterSpace] == "{" {
                    let innerStart = latex.index(after: afterSpace)
                    let end = endOfBraceGroup(in: latex, open: afterSpace)
                    let innerEnd = end > innerStart ? latex.index(before: end) : innerStart
                    if innerStart < innerEnd {
                        output.append(contentsOf: latex[innerStart..<innerEnd])
                    }
                    index = end
                    continue
                }
            }
            output.append(contentsOf: latex[index..<cursor])
            index = cursor
        }
        return output
    }

    private static func rewriteEnvironments(_ latex: String) -> String {
        var output = ""
        var index = latex.startIndex
        while index < latex.endIndex {
            if let span = environmentSpan(in: latex, from: index) {
                // JSON `\n` inside an environment becomes real newlines before
                // this runs. SwiftMath treats some of those as extra rows and
                // then rejects `aligned`. A row break is `\\`, not a newline.
                let body = collapseMathWhitespace(rewriteEnvironments(span.body))
                let target = environmentTarget(name: span.name, body: body)
                if target.isEmpty {
                    output.append(body)
                } else if target == span.name {
                    output.append("\\begin{\(span.name)}")
                    output.append(body)
                    output.append("\\end{\(span.name)}")
                } else {
                    output.append("\\begin{\(target)}")
                    output.append(body)
                    output.append("\\end{\(target)}")
                }
                index = span.end
                continue
            }
            output.append(latex[index])
            index = latex.index(after: index)
        }
        return output
    }

    private struct EnvironmentSpan {
        var name: String
        var body: String
        var end: String.Index
    }

    private static func environmentSpan(in text: String, from index: String.Index) -> EnvironmentSpan? {
        guard text[index...].hasPrefix("\\begin{") else { return nil }
        let nameStart = text.index(index, offsetBy: "\\begin{".count)
        guard let close = text[nameStart...].firstIndex(of: "}") else { return nil }
        let name = String(text[nameStart..<close])
        guard !name.isEmpty else { return nil }
        let bodyStart = text.index(after: close)
        let beginToken = "\\begin{\(name)}"
        let endToken = "\\end{\(name)}"
        var depth = 1
        var cursor = bodyStart
        while cursor < text.endIndex {
            if text[cursor...].hasPrefix(beginToken) {
                depth += 1
                cursor = text.index(cursor, offsetBy: beginToken.count)
                continue
            }
            if text[cursor...].hasPrefix(endToken) {
                depth -= 1
                if depth == 0 {
                    return EnvironmentSpan(
                        name: name,
                        body: String(text[bodyStart..<cursor]),
                        end: text.index(cursor, offsetBy: endToken.count)
                    )
                }
                cursor = text.index(cursor, offsetBy: endToken.count)
                continue
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func collapseMathWhitespace(_ body: String) -> String {
        var output = ""
        var pendingSpace = false
        for character in body {
            if character == "\n" || character == "\t" || character == "\r" {
                pendingSpace = !output.isEmpty
                continue
            }
            if character == " " {
                pendingSpace = !output.isEmpty
                continue
            }
            if pendingSpace { output.append(" ") }
            pendingSpace = false
            output.append(character)
        }
        return output
    }

    private static func environmentTarget(name: String, body: String) -> String {
        guard let mapped = environmentTargets.first(where: { $0.0 == name })?.1 else {
            return name
        }
        if mapped == "aligned", !body.contains("&") {
            return body.contains("\\\\") ? "gather" : ""
        }
        return mapped
    }

    /// Drops one failing command or environment at a time until SwiftMath builds
    /// a list. Returning nil is what used to paint the raw source.
    private static func repairUntilBuildable(_ latex: String) -> String? {
        var current = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        for _ in 0..<24 {
            if current.isEmpty { return nil }
            if buildsSuccessfully(current) { return current }
            if !seen.insert(current).inserted { return nil }
            var error: NSError?
            _ = MTMathListBuilder.build(fromString: current, error: &error)
            guard let message = error?.localizedDescription else { return nil }
            let next: String
            if let command = suffix(of: message, after: "Invalid command \\"), !command.isEmpty {
                next = deletingCommand(command, in: current)
            } else if let environment = suffix(of: message, after: "Unknown environment "), !environment.isEmpty {
                next = strippingEnvironment(environment, in: current)
            } else if let environment = firstEnvironmentName(in: current),
                      message.contains("can only have") || message.contains("Missing") || message.contains("Mismatched") {
                next = strippingEnvironment(environment, in: current)
            } else if let command = firstCommandName(in: current) {
                next = deletingCommand(command, in: current)
            } else {
                return nil
            }
            if next == current { return nil }
            current = next
        }
        return buildsSuccessfully(current) ? current : nil
    }

    private static func suffix(of message: String, after prefix: String) -> String? {
        guard message.hasPrefix(prefix) else { return nil }
        let rest = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : String(rest)
    }

    private static func deletingCommand(_ name: String, in latex: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\\\\(escaped)(?![A-Za-z])\\*?(?:\\s*\\{[^{}]*\\})?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return latex }
        let range = NSRange(latex.startIndex..., in: latex)
        guard let match = regex.firstMatch(in: latex, range: range),
              let full = Range(match.range, in: latex) else { return latex }
        var output = latex
        output.replaceSubrange(full, with: "")
        return output
    }

    private static func strippingEnvironment(_ name: String, in latex: String) -> String {
        let begin = "\\begin{\(name)}"
        let end = "\\end{\(name)}"
        guard let beginRange = latex.range(of: begin) else { return latex }
        var output = latex
        output.replaceSubrange(beginRange, with: "")
        if let endRange = output.range(of: end) {
            output.replaceSubrange(endRange, with: "")
        }
        return output
    }

    private static func firstEnvironmentName(in latex: String) -> String? {
        guard let begin = latex.range(of: "\\begin{") else { return nil }
        let nameStart = begin.upperBound
        guard let close = latex[nameStart...].firstIndex(of: "}") else { return nil }
        let name = String(latex[nameStart..<close])
        return name.isEmpty ? nil : name
    }

    private static func firstCommandName(in latex: String) -> String? {
        var index = latex.startIndex
        while index < latex.endIndex {
            if latex[index] == "\\", let commandEnd = endOfCommandName(in: latex, from: index) {
                let name = String(latex[latex.index(after: index)..<commandEnd])
                if name.allSatisfy(\.isLetter), !name.isEmpty { return name }
            }
            index = latex.index(after: index)
        }
        return nil
    }

    private static func endOfCommandName(in text: String, from index: String.Index) -> String.Index? {
        guard index < text.endIndex, text[index] == "\\" else { return nil }
        var cursor = text.index(after: index)
        guard cursor < text.endIndex else { return nil }
        if text[cursor].isLetter {
            cursor = text.index(after: cursor)
            while cursor < text.endIndex, text[cursor].isLetter {
                cursor = text.index(after: cursor)
            }
            return cursor
        }
        return text.index(after: cursor)
    }

    private static func skipSpaces(in text: String, from index: String.Index) -> String.Index {
        var cursor = index
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func endOfBraceGroup(in text: String, open: String.Index) -> String.Index {
        guard open < text.endIndex, text[open] == "{" else { return open }
        var depth = 0
        var cursor = open
        while cursor < text.endIndex {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" {
                depth -= 1
                if depth == 0 { return text.index(after: cursor) }
            }
            cursor = text.index(after: cursor)
        }
        return cursor
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

    /// SwiftMath display list drawn into a bitmap. `ImageRenderer` captures
    /// this; it does not capture `MTMathUILabel`.
    static func snapshotImage(
        latex: String,
        mode: MathSegmentView.Mode,
        fontSize: CGFloat,
        textColor: Color
    ) -> NSImage? {
        let appearance = NSAppearance(named: .aqua)!
        var resolved = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            let rgb = NSColor(textColor).usingColorSpace(.deviceRGB) ?? .black
            let brightness = (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
            // A dynamic primary color can resolve white when the process has no
            // light appearance. The snapshot card is light, so the glyphs stay dark.
            resolved = brightness > 0.6 ? .black : rgb
        }
        let math = MTMathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: resolved,
            labelMode: mode == .inline ? .text : .display,
            textAlignment: .left
        )
        math.contentInsets = contentInsets
        let (error, drawn) = math.asImage()
        guard let drawn, drawn.size.width > 0.5, drawn.size.height > 0.5 else {
            fputs("SwiftMath asImage failed for \(latex): \(error?.localizedDescription ?? "no image")\n", stderr)
            return nil
        }
        // Materialize the lazy drawing handler. A second bitmap context on the
        // CI runner was staying blank; TIFF generation is the path AppKit uses
        // for this image.
        guard let tiff = drawn.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            fputs("SwiftMath image for \(latex) produced no TIFF (\(drawn.size))\n", stderr)
            return nil
        }
        rep.size = drawn.size
        let image = NSImage(size: drawn.size)
        image.addRepresentation(rep)
        return image
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
