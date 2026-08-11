import Foundation
import FoundationModels

/// Names a conversation the way a person would: from what was actually asked
/// and answered, not from the first few characters the user typed.
///
/// This deliberately does not go through the chat connector. Naming a thread is
/// a throwaway one-line job — it must not spawn a CLI child process, must not
/// spend a subscription turn, and must not queue behind the answer the user is
/// waiting for. It prefers the free on-device model and only falls back to
/// Gemini when Apple Intelligence is unavailable, exactly like reference
/// indexing does.
@MainActor
enum ThreadTitleGenerator {
    /// Titles longer than this are the model ignoring the brief; clipped rather
    /// than rejected, so a slightly wordy answer still beats the raw question.
    static let maxCharacters = 42

    static var isAvailable: Bool {
        FoundationModelsReadingAssistantService.localAvailability.isAvailable
            || AssistantPreferences.geminiEnabled
    }

    /// Returns a short name for the thread, or nil when no model is available
    /// or the reply was unusable. Never throws — an unnamed thread just keeps
    /// its fallback name.
    static func generate(
        selectedText: String,
        surroundingText: String,
        messages: [ThreadMessage]
    ) async -> String? {
        guard let model = model() else { return nil }

        let question = messages.first { $0.role == .user }?.content ?? ""
        let answer = messages.first { $0.role == .assistant }?.content ?? ""
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prompt = userPrompt(
            selectedText: selectedText,
            surroundingText: surroundingText,
            question: question,
            answer: answer
        )

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt)
            return sanitize(response.content)
        } catch {
            return nil
        }
    }

    private static func model() -> (any LanguageModel)? {
        if FoundationModelsReadingAssistantService.localAvailability.isAvailable {
            return SystemLanguageModel.default
        }
        if let apiKey = AssistantPreferences.activeGeminiAPIKey {
            // The cheapest model in the catalog: a four-word title does not
            // need reasoning, and this runs once per thread.
            return GeminiCloudLanguageModel(apiKey: apiKey, modelName: "gemini-3.5-flash-lite")
        }
        return nil
    }

    private static let instructions = """
        You name conversations about mathematical texts. Given a passage a reader
        selected and the question they asked about it, reply with a title for
        that conversation and nothing else.

        Rules:
        - Two to five words. Never a whole sentence.
        - Name the mathematical subject, not the act of asking. "Proof of \
        Cauchy–Schwarz", not "User asks for a proof".
        - Use only words, notation and named results that actually appear in the
        text you are given. Never introduce a theorem or concept that is not
        there — if the passage is too thin to name a subject, describe what it
        claims instead ("Why the Characteristic Is Prime").
        - Title Case, no trailing period, no quotation marks, no LaTeX, no emoji.
        - Output only the title. No preamble, no explanation, no alternatives.

        Examples:
        Question "why is this true" about the triangle inequality -> Why the Triangle Inequality Holds
        Question "whats the proof" about a compactness theorem -> Proof of Compactness
        Question "can you prove this" about uniform continuity -> Uniform Continuity Proof
        """

    private static func userPrompt(
        selectedText: String,
        surroundingText: String,
        question: String,
        answer: String
    ) -> String {
        // Small budgets on purpose: the on-device context window is tight, and
        // the opening of each field already carries what the title needs.
        var prompt = """
            PASSAGE THE READER SELECTED:
            \(selectedText.prefix(600))
            """

        // A one-line selection ("If such a p exists, it is necessarily prime.")
        // names nothing on its own, and a model asked to name it anyway invents
        // a theorem. The paragraph it sits in is what identifies the subject.
        let surroundings = surroundingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedText.count < 200, !surroundings.isEmpty, surroundings != selectedText {
            prompt += """


                THE PARAGRAPH IT SITS IN (context — the subject is named here):
                \(surroundings.prefix(700))
                """
        }

        prompt += """


            THEIR QUESTION:
            \(question.prefix(300))
            """

        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """


                HOW IT WAS ANSWERED (for subject matter only):
                \(answer.prefix(500))
                """
        }

        prompt += "\n\nTitle:"
        return prompt
    }

    /// Models like to wrap a title in quotes, prefix it with "Title:", or add a
    /// second line of commentary. Take the first real line and strip the
    /// decoration; reject anything that still doesn't look like a title.
    static func sanitize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // A stray leading label, then the first non-empty line.
        if let colon = text.range(of: "Title:"), colon.lowerBound == text.startIndex {
            text = String(text[colon.upperBound...])
        }
        text = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*#`.,;: -"))
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        guard text.count >= 3 else { return nil }
        // A markdown list, a refusal, or a full sentence of commentary — all
        // longer than any title worth keeping, and all better replaced by the
        // question itself.
        guard text.count <= maxCharacters * 3 else { return nil }

        guard text.count > maxCharacters else { return text }
        let clipped = text.prefix(maxCharacters)
        guard let lastSpace = clipped.lastIndex(of: " ") else { return String(clipped) + "…" }
        return clipped[..<lastSpace] + "…"
    }
}
