import Foundation

enum ReadingPromptBuilder {
    static func instructions(for context: ReadingContext, provider: ReadingAssistantProvider = .local) -> String {
        var prompt = """
        You are helping someone read "\(context.documentTitle)".

        SELECTED TEXT (their exact focus — answer about this first):
        ---
        \(context.selectedText)
        ---

        SURROUNDING CONTEXT (nearby paragraphs for reference):
        ---
        \(context.surroundingText)
        ---
        """

        if !context.retrievedPassages.isEmpty {
            prompt += """

            RELEVANT PASSAGES (from elsewhere in the document):
            ---
            \(context.retrievedPassages.joined(separator: "\n\n"))
            ---
            """
        }

        // Cloud and CLI models need the reminder that replies render inside the
        // app's LaTeX engine; the on-device model already gets the contract below.
        if provider != .local {
            prompt += """

            IMPORTANT: Your reply is rendered by a LaTeX math engine in the app. Any LaTeX command written outside $...$ or $$...$$ will appear as broken raw text.
            """
        }

        prompt += """

        Content rules:
        - Ground your answer in the text above (and retrieved passages if present).
        - You may use standard mathematical knowledge to actually answer the question; note briefly when a result comes from outside the passage.
        - If the passage defers a result (e.g. to a problem sheet), still state the standard result rather than only saying it is deferred.
        - Do not summarize the whole document.
        - Be precise and concise.
        - Use plain-text section headings (for example, "1. Proof for addition"). Do not use markdown # headings or code fences.

        \(latexOutputContract)
        """

        return prompt
    }

    /// Formats ask-time retrieved passages for inclusion in the model prompt,
    /// clipped to a per-provider character budget (the on-device context
    /// window is small). Returns nil when nothing fits.
    static func retrievedPassagesBlock(_ passages: [String], characterBudget: Int) -> String? {
        guard !passages.isEmpty, characterBudget > 0 else { return nil }
        var clipped: [String] = []
        var used = 0
        for passage in passages {
            let piece = String(passage.prefix(characterBudget - used))
            guard piece.count >= 40 else { break }
            clipped.append(piece)
            used += piece.count
            if used >= characterBudget { break }
        }
        guard !clipped.isEmpty else { return nil }
        return """
        RELEVANT PASSAGES (from elsewhere in the document — mention the page number when you rely on one):

        \(clipped.joined(separator: "\n\n"))
        """
    }

    static func latexRepairInstructions() -> String {
        """
        You fix LaTeX delimiter placement in assistant replies for a math rendering engine.
        Output ONLY the corrected reply. No commentary, no markdown, no code fences.

        \(latexOutputContract)

        Fix rules:
        - Preserve all mathematical meaning and prose wording.
        - Only change delimiter placement and LaTeX syntax needed for valid rendering.
        - Convert \\(...\\) to $...$ and \\[...\\] to $$...$$.
        - Move any bare LaTeX commands (\\frac, \\leq, \\epsilon, \\lambda, etc.) inside delimiters.
        """
    }

    static func latexRepairPrompt(previousOutput: String) -> String {
        """
        Fix the LaTeX delimiters in this reply so every LaTeX command is inside $...$ or $$...$$.
        Output ONLY the corrected reply.

        ---
        \(previousOutput)
        ---
        """
    }

    static let latexOutputContract = """
        MATHEMATICS OUTPUT CONTRACT (mandatory):
        - Use ONLY $...$ for inline math and $$...$$ for display math.
        - Do NOT use \\(...\\), \\[...\\], \\begin{equation}, or markdown math fences.
        - NEVER write LaTeX commands outside delimiters. This includes \\frac, \\leq, \\geq, \\epsilon, \\lambda, \\delta, \\in, \\left, \\right, and \\|.
        - Inline math: short symbols or brief phrases inside prose, e.g. $f$, $g$, $C(X)$, $\\epsilon > 0$, $\\delta_1$.
        - Display math: fractions, norms, inequalities, and multi-step equations on their own line in $$...$$.
        - Use \\frac{a}{b} only inside math delimiters. Prefer display math for fractions.
        - Use \\left| ... \\right| for absolute values and norms inside math delimiters.
        - Do not write raw subscripts like f_y outside math; use $f_y$ or $f_{y}$.

        Good:
        Since $f$ and $g$ are continuous, for any $\\epsilon > 0$ there exists $\\delta > 0$ such that
        $$|f(x) - f(a)| \\leq \\frac{\\epsilon}{2}$$

        Bad (never do this):
        Since f and g are continuous, |f(x) - f(a)| \\leq \\frac{\\epsilon}{2}
        \\left| (f+g)(x) - (f+g)(a) \\right| = \\left| (f(x) - f(a)) + (g(x) - g(a)) \\right|\\leq \\left| f(x) - f(a) \\right| + \\left| g(x) - g(a) \\right|< \\frac{\\epsilon}{2} + \\frac{\\epsilon}{2} = \\epsilon
        """
}
