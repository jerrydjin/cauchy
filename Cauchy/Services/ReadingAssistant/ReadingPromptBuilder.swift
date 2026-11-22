import Foundation

enum ReadingPromptBuilder {
    static func evidenceBudgets(for provider: AssistantConnectorID) -> (statements: Int, passages: Int) {
        provider == .onDevice ? (1_200, 800) : (2_500, 4_000)
    }

    static func instructions(for context: ReadingContext, provider: AssistantConnectorID = .onDevice) -> String {
        var prompt = """
        You are a professor helping someone read "\(context.documentTitle)".
        The first sentence of every reply is the mathematical point, as you would say it at the board. Do not describe the page, the question, or your method before that.

        THE LINES THEY ASKED ABOUT (answer this first):
        ---
        \(context.selectedText)
        ---

        NEARBY LINES (use these if they help; do not mention that they were supplied):
        ---
        \(context.surroundingText)
        ---
        """

        if !context.retrievedPassages.isEmpty {
            prompt += """

            OTHER LINES FROM THE DOCUMENT:
            ---
            \(context.retrievedPassages.joined(separator: "\n\n"))
            ---
            """
        }

        // Cloud and CLI models need the reminder that replies render inside the
        // app's LaTeX engine; the on-device model already gets the contract below.
        if provider != .onDevice {
            prompt += """

            IMPORTANT: Your reply is rendered by a LaTeX math engine in the app. Any LaTeX command written outside $...$ or $$...$$ will appear as broken raw text.
            """
        }

        prompt += """

        Content rules:
        - The first sentence is the reason, spoken like a professor: "Because $h(z_0) = h'(z_0) = 0$, the first two Taylor coefficients vanish, so…". No preamble, no "the text says", no closing summary of how you answered.
        - Name the objects and say why the step follows. Short paragraphs.
        - Ground the reasoning in the lines above. A CITABLE PDF LOCATIONS block accompanies each question when Cauchy has resolved exact page regions. S1 is the lines they asked about, R1/R2/... are numbered statements in order, and P1/P2/... are other lines in order. A source without an ID is context only.
        - Put a source ID such as [S1] or [R1] immediately after each material claim taken from a listed location. Keep separate claims in separate sentences, and cite each substantive paragraph. Keep IDs outside math delimiters. Use only listed IDs; do not invent one or substitute a page number.
        - You may use standard knowledge of the field. Fold it into the explanation without announcing that you are doing so.
        - Never mention how the lines reached you. Do not write any of these: "selected passage", "supplied excerpts", "supplied excerpt", "surrounding context", "extracted text", "extraction artifact", "check the original page".
        - If a formula is obviously garbled (a missing slash, a set difference written with a backslash, a summation sign dropped), read the mathematics that was intended and say nothing about the garbling.
        - Mention a typo only when the printed mathematics itself is inconsistent, in plain words ("the paper writes …; that should be …").
        - If the text defers a result, still give the standard account rather than only saying it is deferred.
        - Do not summarize the whole document.
        - Be precise and concise.
        - Use plain-text section headings (for example, "1. Proof for addition"). Do not use markdown # headings or code fences.

        Evidence boundary (mandatory):
        - End every reply with exactly one machine-readable marker on its own line. The app hides it from the reader.
        - Use [[CAUCHY_BASIS: PDF]] only when every material mathematical or factual claim follows directly from a source with a listed, resolvable ID and each such claim carries its source ID. If no ID is available, do not declare PDF-only.
        - Use [[CAUCHY_BASIS: MIXED]] when any material claim uses established knowledge or an inference that is not stated in the text above. Do not add a sentence whose only job is to announce that split.
        - Use [[CAUCHY_BASIS: INSUFFICIENT]] when the text is too incomplete to answer. Say what it does and does not establish, in the same voice as the rest of the reply, and do not guess.
        - Never cite or imply access to a page that was not included above.

        \(latexOutputContract)
        """

        return prompt
    }

    /// Formats PDF source excerpts for the prompt, clipped to a character
    /// budget. They sit above the passages block, but may be incomplete.
    static func referencedStatementsBlock(_ statements: [String], characterBudget: Int) -> String? {
        guard let clipped = clip(statements, to: characterBudget) else { return nil }
        return """
        NUMBERED STATEMENTS (from the document; read an obvious typesetting glitch as the intended formula and do not mention it):

        \(clipped.joined(separator: "\n\n"))
        """
    }

    /// Formats ask-time retrieved passages for inclusion in the model prompt,
    /// clipped to a per-provider character budget (the on-device context
    /// window is small). Returns nil when nothing fits.
    static func retrievedPassagesBlock(_ passages: [String], characterBudget: Int) -> String? {
        guard let clipped = clip(passages, to: characterBudget) else { return nil }
        return """
        OTHER PASSAGES (from elsewhere in the document — mention the page number when you rely on one):

        \(clipped.joined(separator: "\n\n"))
        """
    }

    /// Source IDs are generated only after the current PDF revalidates the
    /// corresponding page region. Keep this compact so local models receive it.
    static func citableSourcesBlock(_ sources: [AnswerSourceAnchor]) -> String? {
        let lines = sources.compactMap { source -> String? in
            guard let id = source.sourceID else { return nil }
            return "[\(id)] \(source.label), PDF p. \(source.pageIndex + 1)"
        }
        guard !lines.isEmpty else { return nil }
        return "CITABLE PDF LOCATIONS (IDs map to the reader's selection, the numbered statements, and the other passages above):\n"
            + lines.joined(separator: "\n")
    }

    /// Greedily fits items into a character budget, clipping the last one;
    /// fragments under 40 characters are dropped. Returns nil if nothing fits.
    static func clip(_ items: [String], to characterBudget: Int) -> [String]? {
        guard !items.isEmpty, characterBudget > 0 else { return nil }
        var clipped: [String] = []
        var used = 0
        for item in items {
            let piece = String(item.prefix(characterBudget - used))
            guard piece.count >= 40 else { break }
            clipped.append(piece)
            used += piece.count
            if used >= characterBudget { break }
        }
        return clipped.isEmpty ? nil : clipped
    }

    static func latexRepairInstructions() -> String {
        """
        You fix LaTeX delimiter placement in assistant replies for a math rendering engine.
        Output ONLY the corrected reply. No commentary, no markdown, no code fences.

        \(latexOutputContract)

        Fix rules:
        - Preserve all technical meaning and prose wording.
        - Preserve a final [[CAUCHY_BASIS: PDF]], [[CAUCHY_BASIS: MIXED]], or [[CAUCHY_BASIS: INSUFFICIENT]] marker exactly.
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

        SUPPORTED COMMANDS (the renderer implements a subset of LaTeX — an
        unsupported command makes the whole formula fall back to raw source):
        - Available: \\frac, \\sqrt, \\sum, \\int, \\lim, \\underline, \\overline, \\vec, \\hat,
          \\text, \\mathrm, \\mathbb, \\mathcal, \\mathfrak, \\binom, \\left/\\right, \\langle,
          \\quad, \\cdots, and the usual Greek letters, relations, and arrows.
        - Environments: only cases, matrix, pmatrix, bmatrix, Bmatrix, vmatrix, gather.
        - NEVER use: \\underbrace, \\overbrace, \\overset, \\underset, \\stackrel, \\substack,
          \\xrightarrow, \\boxed, \\tag, \\phantom, \\operatorname, \\pmod, \\dfrac, \\tfrac,
          \\bigl/\\bigr/\\Big, \\begin{align}, \\begin{array}, \\begin{equation}.
        - For an annotated repeated sum, do not reach for \\underbrace — put the
          count in prose: "the sum of $p$ copies of $1$", or write $1+1+\\cdots+1$ ($p$ terms).
        - For multi-line derivations use consecutive $$...$$ blocks, not an align environment.

        Good:
        Since $f$ and $g$ are continuous, for any $\\epsilon > 0$ there exists $\\delta > 0$ such that
        $$|f(x) - f(a)| \\leq \\frac{\\epsilon}{2}$$

        Bad (never do this):
        Since f and g are continuous, |f(x) - f(a)| \\leq \\frac{\\epsilon}{2}
        \\left| (f+g)(x) - (f+g)(a) \\right| = \\left| (f(x) - f(a)) + (g(x) - g(a)) \\right|\\leq \\left| f(x) - f(a) \\right| + \\left| g(x) - g(a) \\right|< \\frac{\\epsilon}{2} + \\frac{\\epsilon}{2} = \\epsilon
        """
}
