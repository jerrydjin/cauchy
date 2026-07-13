import Foundation

enum ReferenceParsing {
    static let namedBlockKeywords = "theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof"

    // \s* (not \s+): PDF text extraction can join a line-wrapped
    // "Definition\n1.5.1" without any separator character.
    static let namedBlockPattern = #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof)\s*(\d+(?:\.\d+)*)"#

    static let equationCitePattern = #"(?i)(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*)?\(\s*(\d+(?:\.\d+)*)\s*\)"#
}
