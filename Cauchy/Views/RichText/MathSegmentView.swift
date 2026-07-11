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
            if let rendered = LaTeXValidator.renderableLatex(from: latex) {
                MathLabelRepresentable(
                    latex: rendered,
                    mode: mode,
                    fontSize: fontSize,
                    textColor: textColor
                )
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

    static func sanitize(_ latex: String) -> String {
        var value = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: " \\,", with: " ")
        value = value.replacingOccurrences(of: "\\,", with: " ")

        for (unsupported, supported) in commandAliases {
            value = value.replacingOccurrences(of: unsupported, with: supported)
        }

        return value
    }

    static func renderableLatex(from latex: String) -> String? {
        let base = sanitize(latex)
        let candidates = uniqueCandidates([
            base,
            normalizePlainBars(base),
            normalizeEscapedBars(base),
        ])

        for candidate in candidates where buildsSuccessfully(candidate) {
            return candidate
        }
        return nil
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

private struct MathLabelRepresentable: NSViewRepresentable {
    let latex: String
    let mode: MathSegmentView.Mode
    let fontSize: CGFloat
    let textColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        configure(label, fittedFontSize: fontSize, containerWidth: nil, coordinator: context.coordinator)
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        configure(
            label,
            fittedFontSize: context.coordinator.fittedFontSize ?? fontSize,
            containerWidth: context.coordinator.containerWidth,
            coordinator: context.coordinator
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        let containerWidth = proposal.width
        let fitted = fittedMetrics(
            for: nsView,
            containerWidth: containerWidth,
            coordinator: context.coordinator
        )
        context.coordinator.fittedFontSize = fitted.fontSize
        context.coordinator.containerWidth = containerWidth
        configure(
            nsView,
            fittedFontSize: fitted.fontSize,
            containerWidth: containerWidth,
            coordinator: context.coordinator
        )
        return fitted.size
    }

    private func configure(
        _ label: MTMathUILabel,
        fittedFontSize: CGFloat,
        containerWidth: CGFloat?,
        coordinator: Coordinator
    ) {
        label.displayErrorInline = false
        label.labelMode = mode == .inline ? .text : .display
        label.textAlignment = mode == .display ? .center : .left
        label.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        label.fontSize = fittedFontSize
        label.textColor = NSColor(textColor)
        label.latex = latex

        if mode == .display, let containerWidth, containerWidth.isFinite, containerWidth > 0 {
            label.frame.size.width = containerWidth
        }
    }

    private func fittedMetrics(
        for label: MTMathUILabel,
        containerWidth: CGFloat?,
        coordinator: Coordinator
    ) -> (fontSize: CGFloat, size: CGSize) {
        configure(label, fittedFontSize: fontSize, containerWidth: nil, coordinator: coordinator)
        let intrinsic = label.fittingSize
        guard intrinsic.width > 0, intrinsic.height > 0 else {
            return (fontSize, intrinsic)
        }

        guard let containerWidth, containerWidth.isFinite, containerWidth > 0 else {
            return (fontSize, intrinsic)
        }

        if mode == .display {
            let scale = min(1, containerWidth / intrinsic.width)
            let fittedFontSize = max(11, fontSize * scale)
            configure(label, fittedFontSize: fittedFontSize, containerWidth: containerWidth, coordinator: coordinator)
            let fitted = label.fittingSize
            return (
                fittedFontSize,
                CGSize(width: containerWidth, height: fitted.height)
            )
        }

        if intrinsic.width <= containerWidth {
            return (fontSize, intrinsic)
        }

        let scale = containerWidth / intrinsic.width
        let fittedFontSize = max(11, fontSize * scale)
        configure(label, fittedFontSize: fittedFontSize, containerWidth: nil, coordinator: coordinator)
        let fitted = label.fittingSize
        return (fittedFontSize, fitted)
    }

    final class Coordinator {
        var fittedFontSize: CGFloat?
        var containerWidth: CGFloat?
    }
}
