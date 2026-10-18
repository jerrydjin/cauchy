import Foundation
import PDFKit

enum LearningError: LocalizedError {
    case invalidRange
    case noText
    case sourceTooLong
    case sourceChanged
    case invalidResponse
    case ungroundedLesson
    case repeatedQuestion
    case invalidStudyMap
    case incompleteProof
    case invalidCourse
    case courseTooLong

    var errorDescription: String? {
        switch self {
        case .invalidRange: "Choose a range of up to six pages within this PDF."
        case .noText: "This section has too little readable PDF text. Select a passage with a complete explanation; scanned pages need a text layer."
        case .sourceTooLong: "This section is too long for the selected model. Select a shorter passage or fewer pages."
        case .sourceChanged: "The saved passage no longer matches this PDF. Start a new section from the current document."
        case .invalidResponse: "The tutor returned an incomplete response. Try again or choose another model."
        case .ungroundedLesson: "The tutor could not anchor this lesson to the supplied text. Select a clearer, complete passage and try again."
        case .repeatedQuestion: "The tutor repeated an earlier problem. Try again to get a fresh exit check."
        case .invalidStudyMap: "The study map did not account for the supplied pages, proofs, or source references reliably. Earlier mapped pages are saved. Retry the remaining pages or choose another model."
        case .incompleteProof: "The tutor did not supply a complete, source-grounded argument with justified steps. This proof requirement remains open. Choose a complete source passage and retry."
        case .invalidCourse: "Cauchy couldn’t reliably connect all the identified topics into a learning path. Your document inventory is saved. Try preparing the path again."
        case .courseTooLong: "The selected model couldn’t fit the complete course inventory, even after organizing it into regions. Your notes and identified topics are saved. Choose an assistant with more capacity and prepare the path again."
        }
    }
}

@MainActor
enum LearningSourceBuilder {
    static func pageRange(first: String, last: String, pageCount: Int) throws -> ClosedRange<Int> {
        guard let first = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)),
              let last = Int(last.trimmingCharacters(in: .whitespacesAndNewlines)),
              first >= 1, last >= first, last <= pageCount, last - first < 6 else {
            throw LearningError.invalidRange
        }
        return first...last
    }

    static func pages(_ range: ClosedRange<Int>, in document: PDFDocument, map: LearningStudyMap? = nil) throws -> LearningSource {
        guard range.lowerBound >= 1, range.upperBound <= document.pageCount,
              range.count <= 6 else { throw LearningError.invalidRange }
        let passages = try range.map { page -> LearningSourcePassage in
            guard let text = document.page(at: page - 1)?.string else { throw LearningError.noText }
            if let map, map.latestCorrection(for: page - 1) != nil {
                let passage = try map.passage(pageIndex: page - 1, originalText: text)
                guard LearningSource.normalized(passage.text).count >= 60 else { throw LearningError.noText }
                return passage
            }
            guard LearningSource.normalized(text).count >= 60 else { throw LearningError.noText }
            return LearningSourcePassage(pageIndex: page - 1, text: text)
        }
        return LearningSource(passages: passages)
    }

    static func selection(_ text: String, pageIndex: Int, in document: PDFDocument) throws -> LearningSource {
        guard LearningSource.normalized(text).count >= 60 else { throw LearningError.noText }
        let source = LearningSource(passages: [.init(pageIndex: pageIndex, text: text)])
        guard matches(source, document: document) else { throw LearningError.sourceChanged }
        return source
    }

    static func matches(_ source: LearningSource, document: PDFDocument, map: LearningStudyMap? = nil) -> Bool {
        !source.passages.isEmpty && source.passages.allSatisfy { passage in
            guard passage.pageIndex >= 0, let text = document.page(at: passage.pageIndex)?.string else { return false }
            if let correction = passage.correction {
                guard let latest = map?.latestCorrection(for: passage.pageIndex) else { return false }
                return correction.pageIndex == passage.pageIndex && correction.originalText == text
                    && latest.id == correction.id && latest.correctedText == correction.correctedText
                    && latest.originalText == correction.originalText && latest.note == correction.note
                    && latest.previousID == correction.previousID
                    && passage.text == correction.correctedText
            }
            guard map?.latestCorrection(for: passage.pageIndex) == nil else { return false }
            let selected = LearningSource.normalized(passage.text)
            return !selected.isEmpty && LearningSource.normalized(text).contains(selected)
        }
    }
}
