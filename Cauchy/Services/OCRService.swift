import Foundation
import Vision

struct OCRTextObservation: Sendable {
    let text: String
    let confidence: Float
}

struct OCRResult: Sendable {
    let rawText: String
    let observations: [OCRTextObservation]
    let latexSnippet: String
}

actor OCRService {
    static let shared = OCRService()

    func recognizeText(in image: CGImage) async throws -> OCRResult {
        let rawText = try await performRecognition(on: image)
        let latex = LaTeXFormatter.format(rawText)
        return OCRResult(rawText: rawText, observations: [], latexSnippet: latex)
    }

    private func performRecognition(on image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try Self.recognizeSync(in: image)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func recognizeSync(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["∫", "∑", "∀", "∃", "lemma", "QED", "theorem", "proof"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }
}
