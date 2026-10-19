import Foundation

enum ReferenceParsing {
    static let namedBlockKeywords = "theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof"

    // \s* (not \s+): PDF text extraction can join a line-wrapped
    // "Definition\n1.5.1" without any separator character.
    // A single capital is a statement number ("Theorem B", "Remark A.0.5").
    // It has to stand alone: "Lemmas 4.6" is not lemma s, and "Theorem AB" is not theorem A.
    static let namedBlockPattern = #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof)\s*(\d+(?:\.\d+)*|(?<=\s)(?-i:[A-Z])(?:\.\d+)*(?![A-Za-z]))"#

    // "(A.2)" is an appendix tag. "SO(2)" is a group, not equation 2.
    static let equationCitePattern = #"(?i)(?<![A-Za-z])(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*)?\(\s*((?-i:[A-Z])(?:\.\d+)+|\d+(?:\.\d+)*)\s*\)"#

    // The optional panel suffix belongs to the mention, not the figure's
    // identity: "Fig. 3a,b" links to the numbered Figure 3 object.
    static let figurePattern = #"(?i)\bfig(?:ure)?\.?\s*(\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?\b"#

    // Paired plural citations such as "Figures 1e and 3a,b" refer to two
    // distinct figures. Capture each printed number with its panel suffix.
    static let pairedFiguresPattern = #"(?i)\b(?:figures|figs\.)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\s*(?:and|&|,)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\b"#
}
