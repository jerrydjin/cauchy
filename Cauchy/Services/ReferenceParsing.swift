import Foundation

enum ReferenceParsing {
    /// PDF fonts print "fi" as the single character ﬁ, and the same for fl,
    /// ff, ffi, and ffl. A keyword written with the two letters does not match
    /// that spelling, so "Deﬁnition 2.1" would never be indexed. The inserted
    /// group is non-capturing, so pattern group numbers stay the same.
    /// `ReferenceKind.fromKeyword` folds the captured word back to ASCII.
    static func foldingLigatures(_ pattern: String) -> String {
        let pairs = [
            ("ffi", "(?:ffi|\u{FB03})"),
            ("ffl", "(?:ffl|\u{FB04})"),
            ("ff", "(?:ff|\u{FB00})"),
            ("fi", "(?:fi|\u{FB01})"),
            ("fl", "(?:fl|\u{FB02})"),
        ]
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let rest = pattern[index...]
            if let pair = pairs.first(where: { rest.hasPrefix($0.0) }) {
                result += pair.1
                index = pattern.index(index, offsetBy: pair.0.count)
            } else {
                result.append(pattern[index])
                index = pattern.index(after: index)
            }
        }
        return result
    }

    /// Full words, plus the period-marked abbreviations Thm. Lem. Prop. Cor. Def.
    /// The period is required. "Thm 3.2" and "lem (11)" are not statement
    /// references, so a parenthesized equation is not read as a lemma.
    /// A lowercase full word is the noun, not the label: "the definition (3.2)"
    /// is equation 3.2. "Definition (2.5)" keeps the capital and stays a definition.
    /// `ReferenceKind.fromKeyword` does not map these abbreviations. The
    /// detector does, so a search for "def" does not become a kind filter.
    static let namedBlockKeywords = foldingLigatures(
        "theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof|thm\\.|lem\\.|prop\\.|cor\\.|def\\."
    )

    // \s* (not \s+): PDF text extraction can join a line-wrapped
    // "Definition\n1.5.1" without any separator character.
    // Appendices also use labels such as "Remark A.0.5". Keep the letter form
    // scoped to dotted labels so an ordinary word after "Remark" is not a number.
    static let namedBlockPattern = foldingLigatures(
        #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof|thm\.|lem\.|prop\.|cor\.|def\.)\s*(\d+(?:\.\d+)*|[A-Z](?:\.\d+)+)"#
    )

    static let referenceNumberPattern = #"\d+(?:\.\d+)*|[A-Z](?:\.\d+)+"#

    /// "Lemmas 4.6", "Lemmas 3.1, 3.2 and 3.4", and "Lem. 2, 3, and 4".
    /// The abbreviation needs its period. A single number is a one-item list.
    static let pluralBlockPattern = foldingLigatures(
        #"(?i)\b(theorems|lemmas|propositions|corollaries|definitions|exercises|examples|remarks|proofs|thm\.|lem\.|prop\.|cor\.|def\.)\s*((?:\#(referenceNumberPattern))(?:\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?(?:\#(referenceNumberPattern)))*)"#
    )

    /// "Theorem 6 and 7" and "Theorem 3.1, 3.4 and 3.5" name every number.
    /// A singular word with one number stays on the named pattern, so the
    /// list requires a second number. "Theorem 6 and the bound" is only 6.
    static let singularListPattern = foldingLigatures(
        #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof)\s*((?:\#(referenceNumberPattern))(?:\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?(?:\#(referenceNumberPattern)))+)"#
    )

    /// Group 2 is a subequation part letter, as in "(2.7a)" or "(7a)". A dotted
    /// number always keeps the letter. A bare integer keeps it only when the
    /// same text prints another part letter, so "(7a)" and "(7b)" are equation
    /// 7 and a lone "(1a)" is not.
    /// An appendix tag "(A.1)" or "(B.10)" is that equation. The letter stays
    /// uppercase, so "(a.1)" is not one, and a bare "(A)" is not one either.
    static let equationCitePattern = #"(?i:(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*))?\(\s*([A-Z](?:\.\d+)+|\d+(?:\.\d+)*)(?i:([a-z]))?\s*\)"#

    // The optional panel suffix belongs to the mention, not the figure's
    // identity: "Fig. 3a,b" links to the numbered Figure 3 object.
    static let figurePattern = foldingLigatures(
        #"(?i)\bfig(?:ure)?\.?\s*(\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?\b"#
    )

    // Paired plural citations such as "Figures 1e and 3a,b" refer to two
    // distinct figures. Capture each printed number with its panel suffix.
    static let pairedFiguresPattern = foldingLigatures(
        #"(?i)\b(?:figures|figs\.)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\s*(?:and|&|,)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\b"#
    )

    /// A bracket label such as "12", "IK99", "CCC+18", "Ben17", or "BO09b".
    /// The optional trailing letter is the disambiguator some author–year keys use.
    static let bibliographyKey = #"(?:\d+|[A-Z][A-Za-z]*(?:\+[A-Za-z]*)?\d{2,4}[a-z]?)"#

    /// The inside of a bracket citation: "[12]", "[12, Theorem 3.2]", "[IK99, Lemma 1.15]".
    /// A text-layer line break may fall inside the bracket, as in
    /// "[17,\nTheorem 3.31(c)]". The body is collapsed before it is parsed.
    static let bracketCitationBody = #"\[([^\[\]]{1,180})\]"#

    /// "(Smith 2019)" or "(Smith et al. 2019)".
    static let authorYearParenthetical = #"\(([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s+((?:19|20)\d{2})\)"#

    /// "Smith et al. [2019]" or "Smith [2019]".
    static let authorYearBracket = #"([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s*\[((?:19|20)\d{2})\]"#
}
