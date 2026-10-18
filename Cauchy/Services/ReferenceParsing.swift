import Foundation

enum ReferenceParsing {
    static let namedBlockKeywords = "theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof"

    // Running text abbreviates the same headings ("Thm.", "Thm", "Prop.",
    // "Lem.", "Cor.", "Def."). Eq. and Fig. stay on the equation and figure
    // patterns, which already accept the short form.
    static let singularNamedKeyword = #"theorem|thm\.?|lemma|lem\.?|proposition|prop\.?|corollary|cor\.?|definition|def\.?|exercise|example|remark|proof"#

    static let pluralNamedKeyword = #"theorems|lemmas|propositions|corollaries|definitions|exercises|examples|remarks|proofs"#

    /// Printed statement number, including an appendix label such as A.0.5.
    /// The letter form stays dotted so a word after "Remark" is not a number.
    static let referenceNumber = #"(?:\d+(?:\.\d+)*|[A-Z](?:\.\d+)+)"#

    // \s* (not \s+): PDF text extraction can join a line-wrapped
    // "Definition\n1.5.1" without any separator character.
    // Appendices also use labels such as "Remark A.0.5". Keep the letter form
    // scoped to dotted labels so an ordinary word after "Remark" is not a number.
    static let namedBlockPattern = #"(?i)\b(\#(singularNamedKeyword))\s*(\#(referenceNumber))"#

    /// A plural heading introduces every printed number, not only the first:
    /// "Theorems 2.1 and 2.3", "Lemmas 3.1, 3.2 and 3.4", "Theorems 2.1–2.3".
    static let namedBlockListPattern = #"(?i)\b(\#(pluralNamedKeyword))\s*(\#(referenceNumber)(?:\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?\#(referenceNumber))+)"#

    static let equationCitePattern = #"(?i)(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*)?\(\s*(\d+(?:\.\d+)*)\s*\)"#

    // The optional panel suffix belongs to the mention, not the figure's
    // identity: "Fig. 3a,b" links to the numbered Figure 3 object.
    static let figurePattern = #"(?i)\bfig(?:ure)?\.?\s*(\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?\b"#

    // Paired plural citations such as "Figures 1e and 3a,b" refer to two
    // distinct figures. Capture each printed number with its panel suffix.
    static let pairedFiguresPattern = #"(?i)\b(?:figures|figs\.)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\s*(?:and|&|,)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\b"#

    /// Locator opening a bracket citation, e.g. "12, " in "[12, Theorem 3.2]".
    /// The statement inside names a result in the cited work.
    static let bibliographyQualifierPrefix = #"\s*(?:see\s+)?\d+(?:\s*[-–—]\s*\d+)?(?:\s*,\s*\d+(?:\s*[-–—]\s*\d+)?)*\s*,\s*"#

    static func kind(forKeyword keyword: String) -> ReferenceKind? {
        let normalized = keyword
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let kind = ReferenceKind.fromKeyword(normalized) {
            return kind
        }
        switch normalized {
        case "theorems", "thm":
            return .theorem
        case "lemmas", "lem":
            return .lemma
        case "propositions", "prop":
            return .proposition
        case "corollaries", "cor":
            return .corollary
        case "definitions", "def":
            return .definition
        case "exercises":
            return .exercise
        case "examples":
            return .example
        case "remarks":
            return .remark
        case "proofs":
            return .proof
        default:
            return nil
        }
    }
}
