import Foundation

enum ReferenceIndexPromptBuilder {
    static let maxPageCharacters = 12_000

    /// The on-device model's context window is ~4k tokens, shared with
    /// instructions and the generated output — page text gets a tighter budget.
    static let maxPageCharactersOnDevice = 6_000

    /// Compact instructions for the on-device guided-generation path: the
    /// output shape is enforced by the @Generable schema, so all JSON-format
    /// prose is dropped to leave room in the small context window.
    static let onDeviceInstructions = """
    You extract numbered academic references (theorems, lemmas, definitions, propositions, equations, etc.) from one PDF page. The document may be from any field — pure mathematics, machine learning, the sciences — so take every subject and every name from the page itself.

    Rules:
    - Include ONLY numbered references that appear in the provided page text. Do not invent any.
    - Keep reference numbers exactly as printed (e.g. "1.4", "2.3.1").
    - name is the printed title only, e.g. "Definition 3.2 (Compactness)" → name "Compactness", "Assumption 2 (Bounded Gradients)" → name "Bounded Gradients"; leave empty when none is printed. Never carry a name over from these examples — take it only from this page.
    - Extract definitions/statements introduced here, not citations such as "by Theorem 2.1" or "the proof of Theorem 2.1". A mention does not define a reference.
    - For equations: the body is ONLY the equation itself, no surrounding prose.
    - For theorems/lemmas/definitions/examples: the body is ONLY the statement, never the proof.
    - Write all mathematics inside $...$ (inline) or $$...$$ (display) LaTeX delimiters; never emit LaTeX commands outside delimiters. Prose stays plain text.
    - Fix PDF extraction artifacts: ℝ → $\\mathbb{R}$, unicode sub/superscripts, norm bars ‖x‖ → $\\left\\| x \\right\\|$, broken spacing.
    - Prefer \\leq and \\geq over \\leqslant and \\geqslant.
    - Ignore table-of-contents, index, and list-of-results pages: extract a reference only when its full statement or equation body appears on this page, not just its title and a page number.
    - If the page has no numbered references, return an empty list.
    """

    static let textArtifactHints = """
    Text-layer artifact hints (when no image is provided):
    - Map double-struck unicode to LaTeX: ℝ → $\\mathbb{R}$, ℕ → $\\mathbb{N}$, ℤ → $\\mathbb{Z}$, ℂ → $\\mathbb{C}$
    - Map norm bars: ‖x‖ → $\\left\\| x \\right\\|$ inside math delimiters
    - Preserve reference numbers exactly as in the text layer
    """

    static let instructions = """
    You extract numbered academic references from one PDF page and format them for display.
    Output ONLY valid JSON. No commentary, markdown, or code fences.

    JSON schema:
    {
      "references": [
        {
          "kind": "equation",
          "number": "1.4",
          "formatted_body": "$$x + y = z$$",
          "name": null
        }
      ]
    }

    Allowed kind values: theorem, lemma, proposition, corollary, definition, exercise, example, remark, proof, equation.

    Rules:
    - Include ONLY references that appear on this page in the provided text.
    - Do not invent references.
    - "name" is the reference's printed title when one exists — e.g. "Definition 3.2 (Compactness)" has name "Compactness", "Proposition 1 (Sample Complexity)" has name "Sample Complexity". Use null when no title is printed, and never reuse a name from these examples: the document may be about anything, and a borrowed name is worse than none.
    - Extract definitions/statements introduced here, not citations such as "by Theorem 2.1" or "the proof of Theorem 2.1". A mention does not define a reference.
    - For equations: formatted_body is ONLY the equation, no surrounding prose.
    - For theorems/lemmas/definitions/examples: formatted_body is ONLY the statement, never the proof.
    - Keep prose as plain text outside math delimiters.
    - Do not use markdown headings or code fences.
    - Fix PDF extraction artifacts: unicode subscripts/superscripts, norm bars, broken spacing.
    - If the page has no numbered references, return {"references": []}.
    - formatted_body must be parseable by a strict LaTeX engine (SwiftMath).
    - Prefer \\leq and \\geq over \\leqslant and \\geqslant.
    - Use \\left\\| ... \\right\\| for norms; use single bars | ... | for absolute values. Never change an absolute value into a norm.

    \(textArtifactHints)

    \(ReadingPromptBuilder.latexOutputContract)
    """

    static let visionInstructions = """
    \(instructions)

    Vision rules (when a page image is attached):
    - The image is ground truth for math symbols, underlines, overlines, fractions, matrices, and layout.
    - The text layer is ground truth for reference numbers (Theorem 2.1, (1.10)) and prose wording.
    - When image and text disagree on math content, trust the image.
    - Reconstruct underlines, overlines, tensor notation, and stacked fractions from what you see.
    """

    static func userPrompt(pageText: String, pageIndex: Int) -> String {
        """
        Extract and format every numbered reference on PDF page \(pageIndex + 1).

        Page text:
        ---
        \(truncatedPageText(pageText))
        ---
        """
    }

    /// On-device prompt: assumes the caller already budgeted `pageText` to fit
    /// the small context window (it may be a split fragment of the page).
    static func onDeviceUserPrompt(pageText: String, pageIndex: Int) -> String {
        """
        Extract and format every numbered reference on PDF page \(pageIndex + 1).

        Page text:
        ---
        \(pageText)
        ---
        """
    }

    static func visionUserPrompt(pageText: String, pageIndex: Int) -> String {
        """
        Extract and format every numbered reference on PDF page \(pageIndex + 1).

        You are given:
        1. A rendered image of the page (ground truth for math layout and symbols)
        2. PDF text-layer extraction below (ground truth for reference numbers and prose)

        Page text:
        ---
        \(truncatedPageText(pageText))
        ---
        """
    }

    static func jsonRepairPrompt(previousOutput: String) -> String {
        """
        Your previous response was not valid JSON. Output ONLY a JSON object matching this schema:
        {"references":[{"kind":"equation","number":"1.4","formatted_body":"$$x + y = z$$"}]}
        No commentary, markdown, or code fences.

        Previous output:
        ---
        \(previousOutput)
        ---
        """
    }

    static func truncatedPageText(_ pageText: String) -> String {
        guard pageText.count > maxPageCharacters else { return pageText }
        let end = pageText.index(pageText.startIndex, offsetBy: maxPageCharacters)
        return String(pageText[..<end])
    }

    /// Splits long extracted pages without discarding their tail. Adjacent
    /// chunks overlap so a theorem or equation crossing a hard PDF text-layer
    /// boundary is still presented whole to at least one model call.
    static func pageTextChunks(
        _ pageText: String,
        maxCharacters: Int,
        overlapCharacters: Int = 600
    ) -> [String] {
        guard maxCharacters > 0, pageText.count > maxCharacters else {
            return pageText.isEmpty ? [] : [pageText]
        }

        let overlap = min(max(overlapCharacters, 0), maxCharacters / 3)
        var chunks: [String] = []
        var start = pageText.startIndex

        while start < pageText.endIndex {
            let hardEnd = pageText.index(
                start,
                offsetBy: maxCharacters,
                limitedBy: pageText.endIndex
            ) ?? pageText.endIndex

            if hardEnd == pageText.endIndex {
                chunks.append(String(pageText[start..<hardEnd]))
                break
            }

            // Prefer a paragraph/line boundary in the final third of the
            // budget. Very long unbroken paragraphs fall back to a hard cut.
            let searchStart = pageText.index(start, offsetBy: maxCharacters * 2 / 3)
            let searchRange = searchStart..<hardEnd
            let breakIndex = pageText.range(
                of: "\n\n",
                options: .backwards,
                range: searchRange
            )?.upperBound ?? pageText.range(
                of: "\n",
                options: .backwards,
                range: searchRange
            )?.upperBound ?? hardEnd

            chunks.append(String(pageText[start..<breakIndex]))
            let proposedStart = pageText.index(
                breakIndex,
                offsetBy: -overlap,
                limitedBy: pageText.startIndex
            ) ?? pageText.startIndex
            start = proposedStart > start ? proposedStart : breakIndex
        }

        return chunks
    }
}
