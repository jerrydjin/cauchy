import Foundation
import Vision

struct OCRTextObservation: Sendable {
    let text: String
    let confidence: Float
    /// Vision and PDF page coordinates both use normalized lower-left origin
    /// for the unrotated full-page render used by the probe.
    let boundingBox: NormalizedRect
}

struct OCRResult: Sendable {
    let rawText: String
    let observations: [OCRTextObservation]
    let latexSnippet: String
}

actor OCRService {
    static let shared = OCRService()

    func recognizeText(in image: CGImage, useFastRecognition: Bool = false) async throws -> OCRResult {
        let observations = try await performRecognition(on: image, useFastRecognition: useFastRecognition)
        let rawText = observations.map(\.text).joined(separator: "\n")
        let latex = LaTeXFormatter.format(rawText)
        return OCRResult(rawText: rawText, observations: observations, latexSnippet: latex)
    }

    private func performRecognition(
        on image: CGImage,
        useFastRecognition: Bool
    ) async throws -> [OCRTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let observations = try Self.recognizeSync(
                        in: image,
                        useFastRecognition: useFastRecognition
                    )
                    continuation.resume(returning: observations)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func recognizeSync(
        in cgImage: CGImage,
        useFastRecognition: Bool
    ) throws -> [OCRTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = useFastRecognition ? .fast : .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["∫", "∑", "∀", "∃", "lemma", "QED", "theorem", "proof"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return request.results?.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return OCRTextObservation(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: NormalizedRect(
                    x: box.origin.x,
                    y: box.origin.y,
                    width: box.width,
                    height: box.height
                )
            )
        } ?? []
    }
}

/// A conservative, inspection-only label candidate from local OCR. The whole
/// recognized line is retained and region-anchored; no OCR prose is promoted
/// to verified source text by this detector.
struct OCRReferenceCandidate: Codable, Equatable, Sendable {
    let kind: String
    let number: String
    let rawLine: String
    let normalizedLine: String
    let confidence: Float
    let region: NormalizedRect

    func indexedReference(pageIndex: Int) -> IndexedReference? {
        guard let referenceKind = ReferenceKind(rawValue: kind) else { return nil }
        let reference = DetectedReference(kind: referenceKind, number: number)
        return IndexedReference(
            reference: reference,
            // This is deliberately the visibly imperfect OCR line, not an AI
            // reconstruction that could look authoritative.
            formattedBody: normalizedLine,
            pageIndex: pageIndex,
            evidence: ReferenceEvidence(
                status: .uncertain,
                sourceExcerpt: rawLine,
                matchedText: reference.displayName,
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: rawLine.utf16.count,
                source: .visionOCR,
                matchedRegion: region
            ),
            contentOrigin: .ocrCandidate
        )
    }
}

enum OCRReferenceCandidateDetector {
    private static let headingLabel = try! NSRegularExpression(
        pattern: #"(?i)\b(theorem|lemma|proposition|corollary|definition|exercise|example|remark)\s+([A-Z]?[0-9][0-9.,\s]*[0-9])"#
    )
    private static let commaBetweenDigits = try! NSRegularExpression(
        pattern: #"(?<=\d),(?=\d)"#
    )
    private static let spaceInsideDottedNumber = try! NSRegularExpression(
        pattern: #"(?<=\d)\.\s+(?=\d)"#
    )

    /// Repairs only high-confidence punctuation noise inside a numbered block
    /// heading. It never guesses a character (for example OCR `r` vs `5`).
    static func normalizeReferenceLabel(in line: String) -> String {
        let full = NSRange(line.startIndex..., in: line)
        let matches = headingLabel.matches(in: line, range: full).reversed()
        var result = line
        for match in matches {
            guard let numberRange = Range(match.range(at: 2), in: result) else { continue }
            let number = String(result[numberRange])
            let range = NSRange(number.startIndex..., in: number)
            var normalized = commaBetweenDigits.stringByReplacingMatches(
                in: number,
                range: range,
                withTemplate: "."
            )
            normalized = spaceInsideDottedNumber.stringByReplacingMatches(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized),
                withTemplate: "."
            )
            result.replaceSubrange(numberRange, with: normalized)
        }
        return result
    }

    static func candidates(in result: OCRResult) -> [OCRReferenceCandidate] {
        var candidates: [OCRReferenceCandidate] = []
        var seen = Set<ReferenceKey>()
        for observation in result.observations {
            let normalized = normalizeReferenceLabel(in: observation.text)
            let declarations = LLMReferenceIndexSupport.declarationMatches(in: normalized)
            for declaration in declarations where seen.insert(declaration.reference.key).inserted {
                candidates.append(candidate(
                    declaration.reference,
                    observation: observation,
                    normalizedLine: normalized
                ))
            }

            // OCR commonly emits a right-margin equation label as its own
            // observation. Accept only a parenthesized label well to the right;
            // ordinary inline citations and numbered proof steps stay out.
            let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            for match in ReferenceDetector.allReferences(in: normalized)
                where match.reference.kind == .equation &&
                    String(normalized[match.range]) == trimmed &&
                    observation.boundingBox.x >= 0.65 &&
                    seen.insert(match.reference.key).inserted {
                candidates.append(candidate(
                    match.reference,
                    observation: observation,
                    normalizedLine: normalized
                ))
            }
        }
        return candidates
    }

    private static func candidate(
        _ reference: DetectedReference,
        observation: OCRTextObservation,
        normalizedLine: String
    ) -> OCRReferenceCandidate {
        OCRReferenceCandidate(
            kind: reference.kind.rawValue,
            number: reference.number,
            rawLine: observation.text,
            normalizedLine: normalizedLine,
            confidence: observation.confidence,
            region: observation.boundingBox
        )
    }
}
