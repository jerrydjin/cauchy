import Foundation

enum ReferenceIndexPromptBuilder {
    static let maxPageCharacters = 12_000

    static let textArtifactHints = """
    Text-layer artifact hints (when no image is provided):
    - Map double-struck unicode to LaTeX: ℝ → $\\mathbb{R}$, ℕ → $\\mathbb{N}$, ℤ → $\\mathbb{Z}$, ℂ → $\\mathbb{C}$
    - Map norm bars: ‖x‖ or |x| → $\\left\\| x \\right\\|$ inside math delimiters
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
          "formatted_body": "$$x + y = z$$"
        }
      ]
    }

    Allowed kind values: theorem, lemma, proposition, corollary, definition, exercise, example, remark, proof, equation.

    Rules:
    - Include ONLY references that appear on this page in the provided text.
    - Do not invent references.
    - For equations: formatted_body is ONLY the equation, no surrounding prose.
    - For theorems/lemmas/definitions/examples: formatted_body is ONLY the statement, never the proof.
    - Keep prose as plain text outside math delimiters.
    - Do not use markdown headings or code fences.
    - Fix PDF extraction artifacts: unicode subscripts/superscripts, norm bars, broken spacing.
    - If the page has no numbered references, return {"references": []}.
    - formatted_body must be parseable by a strict LaTeX engine (SwiftMath).
    - Prefer \\leq and \\geq over \\leqslant and \\geqslant.
    - Use \\left\\| ... \\right\\| for norms and absolute values inside math delimiters.

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
}
