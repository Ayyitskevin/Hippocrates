import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class FreshnessAndSearchTests: XCTestCase {
    // MARK: Freshness policy boundaries

    func testDraftPrecedesAnyColor() {
        let verified = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let review = verified.addingTimeInterval(100)
        // Even far past every boundary, an unanswered record stays a draft.
        XCTAssertEqual(
            FreshnessPolicy.state(
                answeredAt: nil,
                verifiedOn: verified,
                reviewAfter: review,
                now: review.addingTimeInterval(10_000)
            ),
            .draft
        )
    }

    func testGreenLastsThroughReviewAfterAndAmberBeginsAfterIt() {
        let answered = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let verified = answered
        let review = verified.addingTimeInterval(1_000)

        XCTAssertEqual(
            FreshnessPolicy.state(answeredAt: answered, verifiedOn: verified, reviewAfter: review, now: verified),
            .green
        )
        // The boundary instant itself is still green.
        XCTAssertEqual(
            FreshnessPolicy.state(answeredAt: answered, verifiedOn: verified, reviewAfter: review, now: review),
            .green
        )
        XCTAssertEqual(
            FreshnessPolicy.state(
                answeredAt: answered,
                verifiedOn: verified,
                reviewAfter: review,
                now: review.addingTimeInterval(1)
            ),
            .amber
        )
    }

    func testRedBeginsAfterOneAdditionalPerRecordInterval() {
        let answered = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let verified = answered
        let review = verified.addingTimeInterval(1_000)
        let redBoundary = review.addingTimeInterval(1_000)

        // The red boundary instant itself is still amber.
        XCTAssertEqual(
            FreshnessPolicy.state(answeredAt: answered, verifiedOn: verified, reviewAfter: review, now: redBoundary),
            .amber
        )
        XCTAssertEqual(
            FreshnessPolicy.state(
                answeredAt: answered,
                verifiedOn: verified,
                reviewAfter: review,
                now: redBoundary.addingTimeInterval(1)
            ),
            .red
        )
    }

    func testNonpositiveWindowFailsSafeToRed() {
        let verified = Date(timeIntervalSinceReferenceDate: 4_000_000)
        XCTAssertEqual(
            FreshnessPolicy.state(
                answeredAt: verified,
                verifiedOn: verified,
                reviewAfter: verified,
                now: verified
            ),
            .red
        )
    }

    // MARK: Re-verification

    private func answeredQuestion(in context: ModelContext) throws -> DIQuestion {
        var values = DIDraftValues()
        values.questionText = "Is linezolid safe with sertraline?"
        values.answerText = "Monitor for serotonin syndrome."
        let question = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: [],
            in: context
        )
        try DIQuestionService.markAnswered(
            questionID: question.id,
            verifiedOn: question.createdAt.addingTimeInterval(3_600),
            stalenessMonths: 12,
            in: context
        )
        return question
    }

    func testReverifyPreservesPerRecordWindowAndAppendsHistory() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let question = try answeredQuestion(in: context)

        let interval = question.reviewAfter.timeIntervalSince(question.verifiedOn)
        let creation = question.createdAt
        let firstVerify = question.verifiedOn
        let secondVerify = firstVerify.addingTimeInterval(7_200)

        try DIQuestionService.reverifyPreservingWindow(
            questionID: question.id,
            on: secondVerify,
            in: context
        )

        XCTAssertEqual(question.verifiedOn, secondVerify)
        XCTAssertEqual(
            question.reviewAfter.timeIntervalSince(secondVerify),
            interval,
            accuracy: 0.5
        )
        XCTAssertEqual(question.verificationHistory, [creation, firstVerify, secondVerify])
        XCTAssertFalse(context.hasChanges)
    }

    func testReverifyRejectsDraftsAndBackwardDates() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = DIDraftValues()
        values.questionText = "Draft question"
        let draft = try DIQuestionService.save(values, questionID: nil, acknowledging: [], in: context)
        XCTAssertThrowsError(
            try DIQuestionService.reverifyPreservingWindow(questionID: draft.id, in: context)
        ) { error in
            XCTAssertEqual(
                error as? DIQuestionServiceError,
                .cannotReverifyDraft(draft.id)
            )
        }

        let answered = try answeredQuestion(in: context)
        XCTAssertThrowsError(
            try DIQuestionService.reverifyPreservingWindow(
                questionID: answered.id,
                on: answered.verifiedOn.addingTimeInterval(-60),
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? DIQuestionServiceError, .verificationMustAdvance)
        }
    }

    // MARK: Search

    func testSearchMatchesGuardedFieldsAndCitationTitlesCaseInsensitively() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var linezolid = DIDraftValues()
        linezolid.questionText = "Is linezolid safe with sertraline?"
        linezolid.answerText = "Monitor for serotonin syndrome."
        _ = try DIQuestionService.save(linezolid, questionID: nil, acknowledging: [], in: context)

        var vanco = DIDraftValues()
        vanco.questionText = "Vancomycin trough timing"
        var citation = DICitationValues()
        citation.title = "Therapeutic monitoring consensus"
        citation.locator = "2020 revision"
        vanco.citations = [citation]
        _ = try DIQuestionService.save(vanco, questionID: nil, acknowledging: [], in: context)

        XCTAssertEqual(try DIQuestionService.search("", in: context).count, 2)
        XCTAssertEqual(try DIQuestionService.search("SEROTONIN", in: context).count, 1)
        XCTAssertEqual(try DIQuestionService.search("consensus", in: context).count, 1)
        XCTAssertEqual(try DIQuestionService.search("linezolid", in: context).first?.questionText, linezolid.questionText)
        XCTAssertEqual(try DIQuestionService.search("nothing matches this", in: context).count, 0)
    }

    func testSearchIgnoresSurroundingWhitespace() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = DIDraftValues()
        values.questionText = "Apixaban renal dosing thresholds"
        _ = try DIQuestionService.save(values, questionID: nil, acknowledging: [], in: context)

        XCTAssertEqual(try DIQuestionService.search("  apixaban  ", in: context).count, 1)
    }
}
