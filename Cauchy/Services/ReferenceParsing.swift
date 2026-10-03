import Foundation

enum ReferenceParsing {
    static let namedBlockKeywords = "theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof"

    // \s* (not \s+): PDF text extraction can join a line-wrapped
    // "Definition\n1.5.1" without any separator character.
    // Appendices also use labels such as "Remark A.0.5". Keep the letter form
    // scoped to dotted labels so an ordinary word after "Remark" is not a number.
    static let namedBlockPattern = #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof)\s*(\d+(?:\.\d+)*|[A-Z](?:\.\d+)+)"#

    static let equationCitePattern = #"(?i)(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*)?\(\s*(\d+(?:\.\d+)*)\s*\)"#

    // The optional panel suffix belongs to the mention, not the figure's
    // identity: "Fig. 3a,b" links to the numbered Figure 3 object.
    static let figurePattern = #"(?i)\bfig(?:ure)?\.?\s*(\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?\b"#

    // Paired plural citations such as "Figures 1e and 3a,b" refer to two
    // distinct figures. Capture each printed number with its panel suffix.
    static let pairedFiguresPattern = #"(?i)\b(?:figures|figs\.)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\s*(?:and|&|,)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\b"#
}
