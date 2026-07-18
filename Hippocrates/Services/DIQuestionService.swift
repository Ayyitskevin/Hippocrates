import Foundation
import SwiftData

/// Value form of a DI record under edit. The form edits these values; nothing
/// touches the model until the save passes the de-identification gate.
struct DIDraftValues: Equatable, Sendable {
    var questionText = ""
    var background = ""
    var answerText = ""
    var searchStrategy = ""
    var requestorRole = RequestorRole.pharmacist
    var questionClass = DIQuestionClass.other
    var urgency = Urgency.routine
    var didFollowUp = false
    var citations: [DICitationValues] = []
}

struct DICitationValues: Equatable, Sendable, Identifiable {
    var id = UUID()
    var tier = SourceTier.tertiary
    var title = ""
    var locator = ""
    var accessedDate = Date.now
    var urlString: String?
}

enum DIQuestionServiceError: Error, Equatable {
    /// The gate: these findings have no acknowledgment for this attempt. The
    /// review sheet must resolve every one before the save can proceed.
    case identifierFindingsRequireReview([DeidentificationFinding])
    case unknownQuestion(UUID)
    case citationTitleRequired
    case citationFieldTooLong(limit: Int)
    case verificationMustFollowCreation
    case invalidStalenessMonths(Int)
    case cannotReverifyDraft(UUID)
    case verificationMustAdvance
}

/// Owns every DI mutation. The de-identification gate is enforced here, not in
/// the UI, so no view can write guarded free text without a completed review
/// (product invariant: DI free text cannot be saved without the gate).
@MainActor
enum DIQuestionService {
    /// I-009: citation title and locator are single-line, bounded, and scanned
    /// by the same gate as the four guarded DI fields.
    nonisolated static var citationFieldCharacterLimit: Int { 200 }

    // MARK: Reading

    static func allQuestions(in context: ModelContext) throws -> [DIQuestion] {
        try context.fetch(FetchDescriptor<DIQuestion>()).sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt > right.createdAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func question(_ id: UUID, in context: ModelContext) throws -> DIQuestion? {
        try context.fetch(FetchDescriptor<DIQuestion>()).first { $0.id == id }
    }

    static func values(of question: DIQuestion) -> DIDraftValues {
        var values = DIDraftValues()
        values.questionText = question.questionText
        values.background = question.background
        values.answerText = question.answerText
        values.searchStrategy = question.searchStrategy
        values.requestorRole = question.requestorRole
        values.questionClass = question.questionClass
        values.urgency = question.urgency
        values.didFollowUp = question.didFollowUp
        values.citations = question.citations
            .sorted { $0.accessedDate < $1.accessedDate }
            .map { citation in
                DICitationValues(
                    id: citation.id,
                    tier: citation.tier,
                    title: citation.title,
                    locator: citation.locator,
                    accessedDate: citation.accessedDate,
                    urlString: citation.urlString
                )
            }
        return values
    }

    // MARK: The gate

    /// Every guarded string is scanned together: the four DI text fields plus
    /// each citation's title and locator (I-009).
    nonisolated static func gateFindings(for values: DIDraftValues) -> [DeidentificationFinding] {
        var fields: [(fieldName: String, text: String)] = [
            (fieldName: "questionText", text: values.questionText),
            (fieldName: "background", text: values.background),
            (fieldName: "answerText", text: values.answerText),
            (fieldName: "searchStrategy", text: values.searchStrategy),
        ]
        for citation in values.citations {
            fields.append((fieldName: "citationTitle", text: citation.title))
            fields.append((fieldName: "citationLocator", text: citation.locator))
        }
        return DeidentificationScanner.findings(in: fields)
    }

    /// Phase 7's restore UI must run this over an archive and complete the
    /// same review before any restore mutation; decode and graph validation
    /// alone are not a privacy review.
    nonisolated static func gateFindings(forArchive archive: BackupArchive) -> [DeidentificationFinding] {
        var fields: [(fieldName: String, text: String)] = []
        for record in archive.payload.questions {
            fields.append((fieldName: "questionText", text: record.questionText))
            fields.append((fieldName: "background", text: record.background))
            fields.append((fieldName: "answerText", text: record.answerText))
            fields.append((fieldName: "searchStrategy", text: record.searchStrategy))
            for tag in record.tags {
                fields.append((fieldName: "tag", text: tag))
            }
        }
        for citation in archive.payload.citations {
            fields.append((fieldName: "citationTitle", text: citation.title))
            fields.append((fieldName: "citationLocator", text: citation.locator))
        }
        return DeidentificationScanner.findings(in: fields)
    }

    // MARK: Saving

    /// Creates or updates a record from values. Throws with the complete
    /// finding list unless every finding carries an acknowledgment from this
    /// attempt. A new record starts as a draft: `answeredAt` stays nil and the
    /// placeholder review window is inert until the record is answered.
    @discardableResult
    static func save(
        _ values: DIDraftValues,
        questionID: UUID?,
        acknowledging acknowledgments: [DeidentificationAcknowledgment],
        in context: ModelContext
    ) throws -> DIQuestion {
        try validateCitations(values.citations)
        let blocking = DeidentificationScanner.unacknowledgedFindings(
            gateFindings(for: values),
            acknowledging: acknowledgments
        )
        guard blocking.isEmpty else {
            throw DIQuestionServiceError.identifierFindingsRequireReview(blocking)
        }

        let question: DIQuestion
        if let questionID {
            guard let existing = try self.question(questionID, in: context) else {
                throw DIQuestionServiceError.unknownQuestion(questionID)
            }
            question = existing
        } else {
            // The initial verification window is a placeholder: freshness
            // policy treats answeredAt == nil as a draft before any
            // green/amber/red computation, and answering re-verifies with the
            // real dates. History therefore starts at the creation timestamp.
            let created = Date.now
            question = DIQuestion(
                createdAt: created,
                verifiedOn: created,
                reviewAfter: created.addingTimeInterval(86_400)
            )
            context.insert(question)
        }

        question.questionText = values.questionText
        question.background = values.background
        question.answerText = values.answerText
        question.searchStrategy = values.searchStrategy
        question.requestorRole = values.requestorRole
        question.questionClass = values.questionClass
        question.urgency = values.urgency
        question.didFollowUp = values.didFollowUp

        // Citations are replaced wholesale from the edited values. Removed
        // rows are deleted explicitly so no orphaned citation survives with a
        // dangling question reference.
        let keptIDs = Set(values.citations.map(\.id))
        for citation in question.citations where keptIDs.contains(citation.id) == false {
            try deleteReplacedCitation(citation, in: context)
        }
        let existingByID = Dictionary(
            uniqueKeysWithValues: question.citations.map { ($0.id, $0) }
        )
        for citationValues in values.citations {
            if let existing = existingByID[citationValues.id] {
                existing.tier = citationValues.tier
                existing.title = citationValues.title
                existing.locator = citationValues.locator
                existing.accessedDate = citationValues.accessedDate
                existing.urlString = citationValues.urlString
            } else {
                context.insert(
                    Citation(
                        id: citationValues.id,
                        question: question,
                        tier: citationValues.tier,
                        title: citationValues.title,
                        locator: citationValues.locator,
                        accessedDate: citationValues.accessedDate,
                        urlString: citationValues.urlString
                    )
                )
            }
        }

        try saveOrRollback(context)
        return question
    }

    /// Answers a draft: the record's verification window becomes real. The
    /// review date derives from the chosen interval (A-006: each record keeps
    /// its own window; later default changes never move it). When the stored
    /// P-005 choice is absent it is recorded here — the first DI use.
    static func markAnswered(
        questionID: UUID,
        verifiedOn: Date,
        stalenessMonths: Int,
        in context: ModelContext
    ) throws {
        guard stalenessMonths > 0 else {
            throw DIQuestionServiceError.invalidStalenessMonths(stalenessMonths)
        }
        guard let question = try question(questionID, in: context) else {
            throw DIQuestionServiceError.unknownQuestion(questionID)
        }
        guard verifiedOn > question.createdAt else {
            throw DIQuestionServiceError.verificationMustFollowCreation
        }
        let calendar = Calendar.current
        let reviewAfter = calendar.date(byAdding: .month, value: stalenessMonths, to: verifiedOn)
            ?? verifiedOn.addingTimeInterval(Double(stalenessMonths) * 2_629_800)

        question.reverify(on: verifiedOn, reviewAfter: reviewAfter)
        question.answeredAt = Date.now

        if let configuration = try AppConfigService.existing(in: context),
           configuration.stalenessIntervalMonths == nil {
            try AppConfigService.setStalenessIntervalMonths(stalenessMonths, on: configuration)
        }
        try saveOrRollback(context)
    }

    /// One-tap re-verification (A-006): appends to the audit history and
    /// slides the record's own review window forward, preserving the exact
    /// per-record interval it was answered with. The app default is never
    /// consulted, so changing it cannot move this record's boundaries.
    static func reverifyPreservingWindow(
        questionID: UUID,
        on verifiedOn: Date = .now,
        in context: ModelContext
    ) throws {
        guard let question = try question(questionID, in: context) else {
            throw DIQuestionServiceError.unknownQuestion(questionID)
        }
        guard question.answeredAt != nil else {
            throw DIQuestionServiceError.cannotReverifyDraft(questionID)
        }
        guard verifiedOn > question.verifiedOn else {
            throw DIQuestionServiceError.verificationMustAdvance
        }
        let interval = question.reviewAfter.timeIntervalSince(question.verifiedOn)
        question.reverify(on: verifiedOn, reviewAfter: verifiedOn.addingTimeInterval(interval))
        try saveOrRollback(context)
    }

    /// A-007: DI volume is small, so search fetches the record set and filters
    /// lowercased strings in memory instead of relying on string predicates.
    static func search(_ query: String, in context: ModelContext) throws -> [DIQuestion] {
        let questions = try allQuestions(in: context)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.isEmpty == false else {
            return questions
        }
        return questions.filter { question in
            var haystacks = [
                question.questionText,
                question.background,
                question.answerText,
                question.searchStrategy,
            ]
            haystacks += question.tags
            haystacks += question.citations.map(\.title)
            return haystacks.contains { $0.lowercased().contains(needle) }
        }
    }

    // MARK: Helpers

    nonisolated static func validateCitations(_ citations: [DICitationValues]) throws {
        for citation in citations {
            let title = citation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false else {
                throw DIQuestionServiceError.citationTitleRequired
            }
            let limit = citationFieldCharacterLimit
            for text in [citation.title, citation.locator, citation.urlString ?? ""] {
                guard text.count <= limit, text.contains(where: { $0.isNewline }) == false else {
                    throw DIQuestionServiceError.citationFieldTooLong(limit: limit)
                }
            }
        }
    }

    /// The one reviewed citation-deletion seam: only a citation replaced or
    /// removed during a gated save of its own question reaches it.
    private static func deleteReplacedCitation(
        _ citation: Citation,
        in context: ModelContext
    ) throws {
        context.delete(citation)
    }

    private static func saveOrRollback(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
