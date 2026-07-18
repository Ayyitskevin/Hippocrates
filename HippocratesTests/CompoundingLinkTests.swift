import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class CompoundingLinkTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return utcCalendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private func recordedIntervention(
        at timestamp: Date,
        in context: ModelContext
    ) throws -> Intervention {
        let types = try TaxonomyService.allInterventionTypes(in: context)
        let type: InterventionType
        if let existing = types.first {
            type = existing
        } else {
            type = try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        }
        let classes = try TaxonomyService.allDrugClasses(in: context)
        let drugClass: DrugClass
        if let existing = classes.first {
            drugClass = existing
        } else {
            drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        }
        return try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .accepted),
            at: timestamp,
            in: context
        )
    }

    // MARK: Linking

    func testCreateLinkedDraftLinksBothDirections() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let intervention = try recordedIntervention(at: date(2026, 3, 1), in: context)

        let question = try DIQuestionService.createLinkedDraft(
            interventionID: intervention.id,
            in: context
        )

        XCTAssertNil(question.answeredAt)
        XCTAssertEqual(intervention.diQuestion?.id, question.id)
        XCTAssertEqual(question.linkedInterventions.map(\.id), [intervention.id])
        XCTAssertFalse(context.hasChanges)

        let linked = try DIQuestionService.linkedInterventions(of: question.id, in: context)
        XCTAssertEqual(linked.map(\.id), [intervention.id])
        XCTAssertEqual(linked.first?.typeLabel, "Renal dose adjustment")
    }

    func testCreateLinkedDraftRejectsAlreadyLinkedAndUnknown() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let intervention = try recordedIntervention(at: date(2026, 3, 1), in: context)
        _ = try DIQuestionService.createLinkedDraft(interventionID: intervention.id, in: context)

        XCTAssertThrowsError(
            try DIQuestionService.createLinkedDraft(interventionID: intervention.id, in: context)
        ) { error in
            XCTAssertEqual(
                error as? DIQuestionServiceError,
                .interventionAlreadyLinked(intervention.id)
            )
        }

        let ghost = UUID()
        XCTAssertThrowsError(
            try DIQuestionService.createLinkedDraft(interventionID: ghost, in: context)
        ) { error in
            XCTAssertEqual(error as? DIQuestionServiceError, .unknownIntervention(ghost))
        }
        XCTAssertEqual(try DIQuestionService.allQuestions(in: context).count, 1)
    }

    // MARK: Year-aware aggregation

    func testYearsSpannedCountsDistinctCalendarYears() {
        let calendar = utcCalendar
        XCTAssertEqual(DIQuestionService.yearsSpanned(by: [], calendar: calendar), 0)
        XCTAssertEqual(
            DIQuestionService.yearsSpanned(
                by: [date(2026, 1, 1), date(2026, 12, 31)],
                calendar: calendar
            ),
            1
        )
        XCTAssertEqual(
            DIQuestionService.yearsSpanned(
                by: [date(2024, 6, 1), date(2025, 6, 1), date(2026, 6, 1), date(2026, 7, 1)],
                calendar: calendar
            ),
            3
        )
    }

    // MARK: Multi-year accumulation through backup

    func testAnswerAccumulatesInterventionsAcrossYearsThroughBackup() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let first = try recordedIntervention(at: date(2024, 5, 10), in: context)
        let question = try DIQuestionService.createLinkedDraft(
            interventionID: first.id,
            in: context
        )

        // Later interventions accumulate on the same answer over the years.
        let second = try recordedIntervention(at: date(2025, 2, 3), in: context)
        let third = try recordedIntervention(at: date(2026, 7, 18), in: context)
        second.diQuestion = question
        third.diQuestion = question
        try context.save()

        XCTAssertEqual(question.linkedInterventions.count, 3)

        let exportDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let archive = try BackupService.makeArchive(from: context, createdAt: exportDate)
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)

        let restoredQuestions = try DIQuestionService.allQuestions(in: destination.mainContext)
        let restored = try XCTUnwrap(restoredQuestions.first)
        XCTAssertEqual(restoredQuestions.count, 1)

        // Both directions survive restore with no duplicate links.
        let restoredLinks = try DIQuestionService.linkedInterventions(
            of: restored.id,
            in: destination.mainContext
        )
        XCTAssertEqual(restoredLinks.count, 3)
        XCTAssertEqual(Set(restoredLinks.map(\.id)), [first.id, second.id, third.id])
        XCTAssertEqual(
            DIQuestionService.yearsSpanned(
                by: restoredLinks.map(\.timestamp),
                calendar: utcCalendar
            ),
            3
        )
        for intervention in try destination.mainContext.fetch(FetchDescriptor<Intervention>()) {
            XCTAssertEqual(intervention.diQuestion?.id, restored.id)
        }

        let reexported = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )
        XCTAssertEqual(archive, reexported)
    }

    // MARK: Ledger surface

    func testLedgerSummaryCarriesLinkIdentity() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let linkedIntervention = try recordedIntervention(at: date(2026, 6, 1), in: context)
        let unlinkedIntervention = try recordedIntervention(at: date(2026, 6, 2), in: context)
        let question = try DIQuestionService.createLinkedDraft(
            interventionID: linkedIntervention.id,
            in: context
        )

        let summaries = try InterventionLedgerService.recent(in: context)
        let linkedSummary = try XCTUnwrap(summaries.first { $0.id == linkedIntervention.id })
        let unlinkedSummary = try XCTUnwrap(summaries.first { $0.id == unlinkedIntervention.id })
        XCTAssertEqual(linkedSummary.diQuestionID, question.id)
        XCTAssertNil(unlinkedSummary.diQuestionID)
    }
}
