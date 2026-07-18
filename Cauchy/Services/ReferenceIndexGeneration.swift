import Foundation
import FoundationModels

/// Guided-generation schema for on-device reference extraction. The framework
/// constrains decoding to this shape, so the small model can never produce
/// unparseable JSON — the parse/repair round-trips of the text path are skipped
/// entirely.
@Generable(description: "Numbered academic references found on one PDF page.")
struct GeneratedPageReferences {
    @Guide(description: "Every numbered reference on the page; empty if none.")
    var references: [GeneratedReference]
}

@Generable
struct GeneratedReference {
    @Guide(description: "The reference type.", .anyOf([
        "theorem", "lemma", "proposition", "corollary", "definition",
        "exercise", "example", "remark", "proof", "equation",
    ]))
    var kind: String

    @Guide(description: "The reference number exactly as printed, e.g. \"1.4\" or \"2.3.1\".")
    var number: String

    @Guide(description: "Only the statement or equation body. Prose stays plain text; all mathematics goes inside $...$ or $$...$$ LaTeX delimiters. Never a proof.")
    var formattedBody: String
}

extension GeneratedPageReferences {
    var asResponse: LLMPageReferenceResponse {
        LLMPageReferenceResponse(references: references.map { reference in
            LLMPageReferenceResponse.Item(
                kind: reference.kind,
                number: reference.number,
                formattedBody: reference.formattedBody
            )
        })
    }
}
