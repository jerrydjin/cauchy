import Foundation

enum LaTeXFormatter {
    private static let symbolMap: [Character: String] = [
        "∫": "\\int",
        "∑": "\\sum",
        "√": "\\sqrt",
        "∞": "\\infty",
        "≤": "\\leq",
        "≥": "\\geq",
        "≠": "\\neq",
        "±": "\\pm",
        "×": "\\times",
        "÷": "\\div",
        "∈": "\\in",
        "∉": "\\notin",
        "⊂": "\\subset",
        "⊃": "\\supset",
        "∀": "\\forall",
        "∃": "\\exists",
        "α": "\\alpha",
        "β": "\\beta",
        "γ": "\\gamma",
        "δ": "\\delta",
        "ε": "\\epsilon",
        "θ": "\\theta",
        "λ": "\\lambda",
        "μ": "\\mu",
        "π": "\\pi",
        "σ": "\\sigma",
        "φ": "\\phi",
        "ω": "\\omega",
        "Δ": "\\Delta",
        "Σ": "\\Sigma",
        "Ω": "\\Omega"
    ]

    static func format(_ raw: String) -> String {
        var result = ""
        var inMath = false

        for char in raw {
            if let latex = symbolMap[char] {
                if !inMath {
                    result += "$"
                    inMath = true
                }
                result += latex
            } else if char.isSuperscript {
                if !inMath {
                    result += "$"
                    inMath = true
                }
                result += "^{\(char.superscriptBase)}"
            } else if char.isSubscript {
                if !inMath {
                    result += "$"
                    inMath = true
                }
                result += "_{\(char.subscriptBase)}"
            } else {
                if inMath, char.isWhitespace || char.isLetter || char.isNumber {
                    result += String(char)
                } else {
                    if inMath {
                        result += "$"
                        inMath = false
                    }
                    result += convertFractionPatterns(in: String(char))
                }
            }
        }

        if inMath {
            result += "$"
        }

        return convertFractionPatterns(in: result)
    }

    private static func convertFractionPatterns(in text: String) -> String {
        let pattern = #"(?<=\$|\s|^)(\d+|\w+)/(\d+|\w+)(?=\$|\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var output = text
        let matches = regex.matches(in: text, range: range).reversed()
        for match in matches {
            guard let fullRange = Range(match.range, in: output),
                  let numRange = Range(match.range(at: 1), in: output),
                  let denRange = Range(match.range(at: 2), in: output) else { continue }
            let replacement = "\\frac{\(output[numRange])}{\(output[denRange])}"
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }
}

private extension Character {
    var isSuperscript: Bool {
        "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ".contains(self)
    }

    var isSubscript: Bool {
        "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎".contains(self)
    }

    var superscriptBase: String {
        switch self {
        case "⁰": "0"
        case "¹": "1"
        case "²": "2"
        case "³": "3"
        case "⁴": "4"
        case "⁵": "5"
        case "⁶": "6"
        case "⁷": "7"
        case "⁸": "8"
        case "⁹": "9"
        case "⁺": "+"
        case "⁻": "-"
        case "⁼": "="
        case "⁽": "("
        case "⁾": ")"
        case "ⁿ": "n"
        default: String(self)
        }
    }

    var subscriptBase: String {
        switch self {
        case "₀": "0"
        case "₁": "1"
        case "₂": "2"
        case "₃": "3"
        case "₄": "4"
        case "₅": "5"
        case "₆": "6"
        case "₇": "7"
        case "₈": "8"
        case "₉": "9"
        case "₊": "+"
        case "₋": "-"
        case "₌": "="
        case "₍": "("
        case "₎": ")"
        default: String(self)
        }
    }
}
