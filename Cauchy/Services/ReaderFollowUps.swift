import CoreGraphics
import Foundation

/// A question offered under a finished reader-chat answer.
///
/// The question is something the open document actually supports: the proof
/// the answer relied on, the next result, a definition that result uses, or
/// an exercise that applies it. `pageIndex` is set only when the question
/// points at a place in the PDF. The pill shows the question alone; tapping
/// it asks the question.
struct SuggestedFollowUp: Equatable, Sendable, Identifiable {
    var question: String
    /// PDF page index. Nil when the question does not point at one page.
    /// The pill does not show it.
    var pageIndex: Int?
    var region: NormalizedRect

    var id: String {
        if let pageIndex { return "\(question)@\(pageIndex)" }
        return question
    }

    var pageLabel: String? {
        guard let pageIndex, pageIndex >= 0 else { return nil }
        return CitationPageLabel.short(firstPageIndex: pageIndex, lastPageIndex: pageIndex)
    }

    /// One button, and the words on it are the question.
    var voiceOverLabel: String { question }

    init(question: String, pageIndex: Int?, region: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 0, height: 0)) {
        self.question = question
        self.pageIndex = pageIndex
        self.region = region
    }
}

/// One numbered statement from the open document, plus the proof that follows
/// it when the page text has one. Built from the reference index; the planner
/// never invents a statement that is not in this list.
struct ReaderFollowUpStatement: Equatable, Sendable {
    var reference: DetectedReference
    var name: String?
    var pageIndex: Int
    var region: NormalizedRect
    var statementText: String
    var proofText: String
    var proofPageIndex: Int?
    var proofRegion: NormalizedRect
    /// Heading anchor in the page's text layer, for the passage wash.
    var headingText: String
    var headingStart: Int
    var headingEnd: Int
    var proofHeadingText: String?
    var proofHeadingStart: Int?
    var proofHeadingEnd: Int?

    init(
        reference: DetectedReference,
        name: String? = nil,
        pageIndex: Int,
        region: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 0, height: 0),
        statementText: String,
        proofText: String = "",
        proofPageIndex: Int? = nil,
        proofRegion: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 0, height: 0),
        headingText: String = "",
        headingStart: Int = 0,
        headingEnd: Int = 0,
        proofHeadingText: String? = nil,
        proofHeadingStart: Int? = nil,
        proofHeadingEnd: Int? = nil
    ) {
        self.reference = reference
        self.name = name
        self.pageIndex = pageIndex
        self.region = region
        self.statementText = statementText
        self.proofText = proofText
        self.proofPageIndex = proofPageIndex
        self.proofRegion = proofRegion
        self.headingText = headingText
        self.headingStart = headingStart
        self.headingEnd = headingEnd
        self.proofHeadingText = proofHeadingText
        self.proofHeadingStart = proofHeadingStart
        self.proofHeadingEnd = proofHeadingEnd
    }
}

/// Picks at most two follow-ups for one finished answer.
///
/// Nothing here calls a model or rewrites the answer. A follow-up is emitted
/// only when a statement in the open document supports it, so an answer that
/// cites nothing in the index shows none. Generic prompts ("Tell me more")
/// are not in the candidate list.
enum ReaderFollowUps {
    static let maximumCount = 2

    private static let provableKinds: Set<ReferenceKind> = [.theorem, .lemma, .proposition, .corollary]
    private static let bannedPhrases = [
        "tell me more", "explain more", "can you elaborate", "what else",
        "go on", "anything else", "more detail", "more about",
    ]

    static func suggest(
        answer: String,
        question: String = "",
        selection: String = "",
        anchors: [AnswerSourceAnchor] = [],
        statements: [ReaderFollowUpStatement],
        alreadyAsked: [String] = []
    ) -> [SuggestedFollowUp] {
        // Only statements the answer, the question, or the selection actually
        // names. The next proposition on the page is not a follow-up.
        let allowed = allowedStatements(
            answer: answer,
            question: question,
            selection: selection,
            anchors: anchors,
            statements: statements
        )
        guard !allowed.isEmpty else { return [] }

        var chosen: [SuggestedFollowUp] = []
        var usedTargets = Set<String>()
        let askedKeys = alreadyAsked.map { questionKey($0) }
        let variedBy = question.isEmpty ? answer : question

        func consider(_ followUp: SuggestedFollowUp?, target: String) {
            guard chosen.count < maximumCount, let followUp else { return }
            let text = followUp.question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isGeneric(text), !isFiller(text) else { return }
            guard !repeatsAsked(text, keys: askedKeys) else { return }
            guard namesOnly(text, allowed: allowed, statements: statements) else { return }
            guard usedTargets.insert(target).inserted else { return }
            var accepted = followUp
            accepted.question = text
            chosen.append(accepted)
        }

        for statement in allowed where provableKinds.contains(statement.reference.kind) {
            let proofTarget = "proof:\(statement.reference.kind.rawValue):\(statement.reference.number)"
            consider(
                proofConceptFollowUp(
                    primary: statement,
                    answer: answer,
                    statements: statements,
                    variedBy: variedBy
                ),
                target: proofTarget
            )
        }
        for statement in allowed where statement.reference.kind == .definition {
            if answerAlreadyStates(statement, in: answer) { continue }
            consider(
                definitionFollowUp(statement, variedBy: variedBy),
                target: targetKey(statement)
            )
        }
        for statement in allowed where provableKinds.contains(statement.reference.kind) {
            if let example = exerciseFollowUp(primary: statement, answer: answer, allowed: allowed) {
                consider(example.followUp, target: example.target)
            }
        }
        return chosen
    }

    /// "What does the proof of X rely on?" and "What does Y build on?" were
    /// the same two chips on every answer, aimed at whatever came next on the
    /// page. A chip that isn't about this question is worse than no chip.
    static func isFiller(_ question: String) -> Bool {
        let lowered = question.lowercased()
        if lowered.contains("rely on") || lowered.contains("relies on") { return true }
        if lowered.contains("build on") || lowered.contains("builds on") || lowered.contains("built on") {
            return true
        }
        return false
    }

    static func isGeneric(_ question: String) -> Bool {
        let lowered = question.lowercased()
        return bannedPhrases.contains { lowered.contains($0) }
    }

    // MARK: - Candidates

    /// "Why does the proof of Proposition 5.3 need compactness?" The concept
    /// is a definition the proof text actually names, and the answer has not
    /// already discussed that name.
    private static func proofConceptFollowUp(
        primary: ReaderFollowUpStatement,
        answer: String,
        statements: [ReaderFollowUpStatement],
        variedBy: String
    ) -> SuggestedFollowUp? {
        guard provableKinds.contains(primary.reference.kind) else { return nil }
        let proof = primary.proofText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard proof.count >= 20 else { return nil }
        guard let concept = conceptNamed(in: proof, answer: answer, statements: statements, excluding: primary) else {
            return nil
        }
        return SuggestedFollowUp(
            question: variedProofQuestion(
                name: primary.reference.displayName,
                concept: concept.questionPhrase,
                seed: variedBy
            ),
            pageIndex: primary.proofPageIndex ?? primary.pageIndex,
            region: located(primary.proofRegion, fallback: primary.region)
        )
    }

    private static func definitionFollowUp(
        _ definition: ReaderFollowUpStatement,
        variedBy: String
    ) -> SuggestedFollowUp {
        let subject: String
        if let name = usableName(definition.name) {
            subject = name.lowercased()
        } else {
            subject = definition.reference.displayName
        }
        let forms = [
            "What does the definition of \(subject) require?",
            "Which condition in the definition of \(subject) is doing the work?",
            "How is \(subject) being used here?",
        ]
        return placeFollowUp(question: forms[stableIndex(variedBy + subject, count: forms.count)], statement: definition)
    }

    private static func variedProofQuestion(name: String, concept: String, seed: String) -> String {
        let forms = [
            "Why does the proof of \(name) use \(concept)?",
            "Where does \(concept) enter the proof of \(name)?",
            "How does \(concept) finish the argument for \(name)?",
            "What fails in the proof of \(name) without \(concept)?",
        ]
        return forms[stableIndex(seed + concept, count: forms.count)]
    }

    private static func stableIndex(_ text: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash = 0
        for byte in text.utf8 {
            hash = (hash &* 33 &+ Int(byte)) % 10_007
        }
        return hash % count
    }

    /// "Try it on f(x) = 1/x." Only when an example or exercise in the
    /// document applies the cited result and writes down a concrete assignment
    /// the answer did not already use.
    private static func exerciseFollowUp(
        primary: ReaderFollowUpStatement,
        answer: String,
        allowed: [ReaderFollowUpStatement]
    ) -> (followUp: SuggestedFollowUp, target: String)? {
        let exercises = allowed.filter {
            $0.reference.kind == .example || $0.reference.kind == .exercise
        }.sorted(by: readsBefore)
        for exercise in exercises {
            let citesPrimary = ReferenceDetector.allReferences(in: exercise.statementText).contains {
                $0.reference.kind == primary.reference.kind
                    && $0.reference.number == primary.reference.number
            }
            guard citesPrimary, let expression = concreteExpression(in: exercise.statementText) else { continue }
            guard answer.range(of: expression, options: .caseInsensitive) == nil else { continue }
            let followUp = placeFollowUp(question: "Try it on \(expression).", statement: exercise)
            return (followUp, targetKey(exercise))
        }
        return nil
    }

    private static func placeFollowUp(question: String, statement: ReaderFollowUpStatement) -> SuggestedFollowUp {
        SuggestedFollowUp(
            question: question,
            pageIndex: statement.pageIndex >= 0 ? statement.pageIndex : nil,
            region: statement.region
        )
    }

    // MARK: - Grounding

    private static func allowedStatements(
        answer: String,
        question: String,
        selection: String,
        anchors: [AnswerSourceAnchor],
        statements: [ReaderFollowUpStatement]
    ) -> [ReaderFollowUpStatement] {
        let corpus = [answer, question, selection].joined(separator: "\n")
        var references = ReferenceDetector.allReferences(in: corpus).map(\.reference)
        for anchor in anchors {
            references.append(contentsOf: ReferenceDetector.allReferences(in: anchor.label).map(\.reference))
        }
        var seen = Set<ReferenceKey>()
        var resolved: [ReaderFollowUpStatement] = []
        for reference in references {
            guard let statement = statements.first(where: {
                $0.reference.kind == reference.kind && $0.reference.number == reference.number
            }) else { continue }
            guard seen.insert(statement.reference.key).inserted else { continue }
            resolved.append(statement)
        }
        return resolved
    }

    /// A chip may name a concept from an allowed proof. It may not name a
    /// numbered statement that this question and answer never touched.
    private static func namesOnly(
        _ question: String,
        allowed: [ReaderFollowUpStatement],
        statements: [ReaderFollowUpStatement]
    ) -> Bool {
        let allowedKeys = Set(allowed.map { $0.reference.key })
        for reference in ReferenceDetector.allReferences(in: question).map(\.reference) {
            let known = statements.contains {
                $0.reference.kind == reference.kind && $0.reference.number == reference.number
            }
            if known, !allowedKeys.contains(reference.key) { return false }
        }
        return true
    }

    private struct NamedConcept {
        var questionPhrase: String
        var index: Int
    }

    private static func conceptNamed(
        in proof: String,
        answer: String,
        statements: [ReaderFollowUpStatement],
        excluding primary: ReaderFollowUpStatement
    ) -> NamedConcept? {
        let definitions = statements.filter {
            $0.reference.kind == .definition && $0.reference.key != primary.reference.key
        }
        var best: NamedConcept?
        for definition in definitions {
            guard let name = usableName(definition.name) else { continue }
            if containsPhrase(name, in: answer) { continue }
            let cited = ReferenceDetector.allReferences(in: proof).contains {
                $0.reference.kind == .definition && $0.reference.number == definition.reference.number
            }
            let named = containsPhrase(name, in: proof)
            guard cited || named else { continue }
            let index = (proof as NSString).range(of: name, options: .caseInsensitive).location
            let position = index == NSNotFound ? (cited ? 0 : Int.max) : index
            if best == nil || position < best!.index {
                best = NamedConcept(questionPhrase: questionPhrase(for: name), index: position)
            }
        }
        return best
    }

    /// A single word stays bare ("compactness"). A longer name takes "the",
    /// so the question still reads as a sentence. Matching uses the printed
    /// name, not this article.
    private static func questionPhrase(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains(" ") && !lowered.hasPrefix("the ") {
            return "the \(lowered)"
        }
        return lowered
    }

    private static func usableName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              (2...48).contains(trimmed.count),
              trimmed.contains(where: \.isLetter),
              trimmed.first?.isNumber != true else { return nil }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...4).contains(words.count) else { return nil }
        guard !trimmed.contains(where: \.isNumber) else { return nil }
        return trimmed
    }

    private static func answerAlreadyStates(_ definition: ReaderFollowUpStatement, in answer: String) -> Bool {
        let body = definition.statementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count >= 40 else { return false }
        let probe = String(body.prefix(40))
        return answer.range(of: probe, options: .caseInsensitive) != nil
    }

    private static func readsBefore(_ lhs: ReaderFollowUpStatement, _ rhs: ReaderFollowUpStatement) -> Bool {
        if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
        let order = lhs.reference.number.localizedStandardCompare(rhs.reference.number)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.reference.kind.rawValue < rhs.reference.kind.rawValue
    }

    private static func targetKey(_ statement: ReaderFollowUpStatement) -> String {
        "\(statement.reference.kind.rawValue):\(statement.reference.number)"
    }

    private static func located(_ region: NormalizedRect, fallback: NormalizedRect) -> NormalizedRect {
        region.width > 0 && region.height > 0 ? region : fallback
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static let assignmentPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z]\([^()\n]{0,24}\)\s*=\s*[0-9][0-9A-Za-z./^+-]{0,16}"#
    )

    /// A concrete assignment such as "f(x) = 1/x". The right-hand side has to
    /// start with a digit so a bare "f(x) = x" is not offered as an exercise.
    private static func concreteExpression(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = assignmentPattern.matches(in: text, range: range)
        let expressions = matches.compactMap { match -> String? in
            guard let span = Range(match.range, in: text) else { return nil }
            var expression = String(text[span]).trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = expression.last, ". ".contains(last) {
                expression.removeLast()
            }
            return expression.isEmpty ? nil : expression
        }
        return expressions.min { $0.count < $1.count }
    }

    /// True when `question` repeats or paraphrases something already asked.
    /// "What is Theorem 5.4 built on?" is the same ask as "What does Theorem
    /// 5.4 build on?". A different ask about the same statement is kept.
    private static func repeatsAsked(_ question: String, keys: [QuestionKey]) -> Bool {
        let followUp = questionKey(question)
        guard !followUp.normalized.isEmpty else { return false }
        for asked in keys {
            if followUp.normalized == asked.normalized { return true }
            if containsTheOther(followUp.normalized, asked.normalized) { return true }
            if sameAsk(followUp, asked) { return true }
        }
        return false
    }

    private struct QuestionKey {
        var normalized: String
        var tokens: Set<String>
        var references: Set<String>
        var intents: Set<String>
    }

    private static let referencePattern = try! NSRegularExpression(
        pattern: #"\b(theorem|lemma|proposition|corollary|definition|example|exercise|thm|lem|prop|cor|def)\s+([0-9]+(?:\.[0-9]+)*)\b"#,
        options: .caseInsensitive
    )

    private static let kindAliases = [
        "thm": "theorem", "lem": "lemma", "prop": "proposition",
        "cor": "corollary", "def": "definition",
    ]

    /// Words that name the kind of question. "built" and "depends" are the
    /// same next step as "build on"; "proof" is a different one.
    private static let intentWords: [String: String] = [
        "build": "basis", "built": "basis", "builds": "basis", "building": "basis",
        "depend": "basis", "depends": "basis", "dependent": "basis",
        "rely": "basis", "relies": "basis", "relied": "basis",
        "based": "basis", "basis": "basis",
        "proof": "proof", "prove": "proof", "proves": "proof", "proved": "proof",
        "definition": "definition", "define": "definition", "defined": "definition",
        "require": "definition", "requires": "definition", "required": "definition",
        "try": "exercise", "tries": "exercise",
    ]

    private static func questionKey(_ text: String) -> QuestionKey {
        let normalized = text.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber || character == "." { return character }
            return " "
        }
        let collapsed = String(normalized)
            .split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                var word = String(token)
                while word.hasSuffix(".") { word.removeLast() }
                return word
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let range = NSRange(collapsed.startIndex..., in: collapsed)
        var references = Set<String>()
        for match in referencePattern.matches(in: collapsed, range: range) {
            guard let kindRange = Range(match.range(at: 1), in: collapsed),
                  let numberRange = Range(match.range(at: 2), in: collapsed) else { continue }
            let rawKind = String(collapsed[kindRange])
            let kind = kindAliases[rawKind] ?? rawKind
            references.insert("\(kind) \(collapsed[numberRange])")
        }
        let tokens = Set(collapsed.split(separator: " ").map(String.init))
        let intents = Set(tokens.compactMap { intentWords[$0] })
        return QuestionKey(normalized: collapsed, tokens: tokens, references: references, intents: intents)
    }

    /// "so, what does theorem 5.4 build on" contains the follow-up. A short
    /// fragment such as "theorem 5.4" does not, or every question about that
    /// statement would disappear.
    private static func containsTheOther(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard longer.contains(shorter) else { return false }
        return shorter.count * 4 >= longer.count * 3
    }

    private static func sameAsk(_ lhs: QuestionKey, _ rhs: QuestionKey) -> Bool {
        guard !lhs.references.isDisjoint(with: rhs.references) else { return false }
        if !lhs.intents.isDisjoint(with: rhs.intents) { return true }
        let shared = lhs.tokens.intersection(rhs.tokens)
        let shorter = min(lhs.tokens.count, rhs.tokens.count)
        return shorter >= 3 && shared.count == shorter
    }
}

/// Turns indexed statements and the page text they were read from into the
/// planner's catalog. An OCR candidate and a statement with no PDF excerpt
/// are left out: a follow-up may not point at text the reader cannot open.
enum ReaderFollowUpCatalog {
    struct PageText: Equatable, Sendable {
        var pageIndex: Int
        var text: String
    }

    struct ProofExcerpt: Equatable, Sendable {
        var text: String
        var pageIndex: Int
        var headingText: String
        var headingStart: Int
        var headingEnd: Int
    }

    static func statements(from blocks: [DocumentBlock], pages: [PageText]) -> [ReaderFollowUpStatement] {
        let byPage = Dictionary(pages.map { ($0.pageIndex, $0.text) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<ReferenceKey>()
        var results: [ReaderFollowUpStatement] = []
        for block in blocks {
            guard seen.insert(block.reference.key).inserted else { continue }
            guard block.reference.kind != .figure, block.contentOrigin != .ocrCandidate else { continue }
            guard let evidence = block.evidence, evidence.effectiveSource == .pdfText else { continue }
            let excerpt = evidence.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard excerpt.count >= 12 else { continue }
            let headingEnd = evidence.matchEndOffset ?? evidence.endOffset
            let proof = proof(
                in: byPage[block.pageIndex] ?? "",
                pageIndex: block.pageIndex,
                afterUTF16: headingEnd,
                nextPage: byPage[block.pageIndex + 1]
            )
            results.append(ReaderFollowUpStatement(
                reference: block.reference,
                name: block.name,
                pageIndex: block.pageIndex,
                statementText: excerpt,
                proofText: proof?.text ?? "",
                proofPageIndex: proof?.pageIndex,
                headingText: evidence.matchedText,
                headingStart: evidence.matchStartOffset ?? evidence.startOffset,
                headingEnd: headingEnd,
                proofHeadingText: proof?.headingText,
                proofHeadingStart: proof?.headingStart,
                proofHeadingEnd: proof?.headingEnd
            ))
        }
        return results
    }

    /// The proof that follows a declaration. The body stops at the next
    /// numbered result, so a later theorem is not swallowed into this one.
    /// A proof that starts the next page is kept; a proof found further down
    /// that page belongs to something else and is ignored.
    static func proof(
        in pageText: String,
        pageIndex: Int,
        afterUTF16 offset: Int,
        nextPage: String? = nil
    ) -> ProofExcerpt? {
        if let found = proof(in: pageText, pageIndex: pageIndex, afterUTF16: offset, limitLines: nil) {
            return found
        }
        guard let nextPage else { return nil }
        return proof(in: nextPage, pageIndex: pageIndex + 1, afterUTF16: 0, limitLines: 6)
    }

    private static func proof(
        in pageText: String,
        pageIndex: Int,
        afterUTF16 offset: Int,
        limitLines: Int?
    ) -> ProofExcerpt? {
        guard let start = stringIndex(in: pageText, utf16: offset) else { return nil }
        let suffix = String(pageText[start...])
        let suffixOrigin = (pageText as NSString).length - (suffix as NSString).length
        var lines = suffix.components(separatedBy: "\n")
        if let limitLines {
            lines = Array(lines.prefix(limitLines))
        }
        guard let headingLine = lines.firstIndex(where: isProofHeading) else { return nil }
        let heading = lines[headingLine].trimmingCharacters(in: .whitespaces)
        var body: [String] = []
        if let inline = inlineProofBody(heading) {
            body.append(inline)
        }
        for line in lines.dropFirst(headingLine + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isStopHeading(trimmed) { break }
            body.append(trimmed)
            if body.joined(separator: " ").count >= 700 { break }
        }
        let text = body.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 20 else { return nil }
        guard let headingRange = suffix.range(of: headingLineText(in: lines[headingLine])) else { return nil }
        let headingStart = suffixOrigin + suffix.utf16.distance(from: suffix.startIndex, to: headingRange.lowerBound)
        let wordLength = ("Proof" as NSString).length
        let page = pageText as NSString
        guard headingStart >= 0, headingStart + wordLength <= page.length else { return nil }
        let word = page.substring(with: NSRange(location: headingStart, length: wordLength))
        return ProofExcerpt(
            text: text,
            pageIndex: pageIndex,
            headingText: word,
            headingStart: headingStart,
            headingEnd: headingStart + wordLength
        )
    }

    private static func headingLineText(in line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    private static func isProofHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^(?i)proof\b"#, options: .regularExpression) != nil else { return false }
        if trimmed.range(of: #"^(?i)proof\s+of\b"#, options: .regularExpression) != nil { return true }
        return trimmed.range(of: #"^(?i)proof\s*[.:]?\s*"#, options: .regularExpression) != nil
    }

    private static func inlineProofBody(_ heading: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(?i)proof\s*[.:]\s*(\S.*)$"#) else { return nil }
        let range = NSRange(heading.startIndex..., in: heading)
        guard let match = regex.firstMatch(in: heading, range: range),
              let body = Range(match.range(at: 1), in: heading) else { return nil }
        let text = String(heading[body]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func isStopHeading(_ line: String) -> Bool {
        if line == "∎" || line == "□" || line.compare("QED", options: .caseInsensitive) == .orderedSame {
            return true
        }
        return line.range(
            of: #"^(?i)(theorem|lemma|proposition|corollary|definition|example|remark|exercise)\s+[A-Z0-9]"#,
            options: .regularExpression
        ) != nil
    }

    private static func stringIndex(in text: String, utf16 offset: Int) -> String.Index? {
        let ns = text as NSString
        guard offset >= 0, offset <= ns.length else { return nil }
        return Range(NSRange(location: offset, length: 0), in: text)?.lowerBound
    }
}
