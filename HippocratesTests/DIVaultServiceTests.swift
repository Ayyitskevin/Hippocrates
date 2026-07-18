import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class DIVaultServiceTests: XCTestCase {
    private func cleanValues() -> DIDraftValues {
        var values = DIDraftValues()
        values.questionText = "Is linezolid safe with sertraline?"
        values.background = "Adult inpatient on stable sertraline therapy."
        values.answerText = "Serotonin syndrome risk exists; monitor closely."
        values.searchStrategy = "Reviewed tertiary references and primary reports."
        values.questionClass = .interaction
        return values
    }

    // MARK: The gate

    func testCleanDraftSavesWithoutAcknowledgments() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let question = try DIQuestionService.save(
            cleanValues(),
            questionID: nil,
            acknowledging: [],
            in: context
        )
        XCTAssertNil(question.answeredAt)
        XCTAssertEqual(question.questionClass, .interaction)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try DIQuestionService.allQuestions(in: context).count, 1)
    }

    func testIdentifierBlocksSaveAndNothingPersists() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        values.background = "Patient MRN: 12345678 on sertraline."

        XCTAssertThrowsError(
            try DIQuestionService.save(values, questionID: nil, acknowledging: [], in: context)
        ) { error in
            guard case let DIQuestionServiceError.identifierFindingsRequireReview(findings)? =
                error as? DIQuestionServiceError
            else {
                XCTFail("expected gate findings")
                return
            }
            XCTAssertEqual(findings.count, 1)
            XCTAssertEqual(findings.first?.category, .medicalRecordNumber)
            XCTAssertEqual(findings.first?.fieldName, "background")
        }
        XCTAssertEqual(try DIQuestionService.allQuestions(in: context).count, 0)
    }

    func testAcknowledgmentForExactTextAllowsSave() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        values.background = "Protocol reference 445566 governs dosing."
        let acknowledgment = DeidentificationAcknowledgment(
            fieldName: "background",
            matchedText: "445566"
        )

        let question = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: [acknowledgment],
            in: context
        )
        XCTAssertEqual(question.background, values.background)
    }

    func testAcknowledgmentDoesNotCoverDifferentTextOrField() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        values.background = "Protocol reference 445566 governs dosing."
        let wrongText = DeidentificationAcknowledgment(
            fieldName: "background",
            matchedText: "999999"
        )
        XCTAssertThrowsError(
            try DIQuestionService.save(values, questionID: nil, acknowledging: [wrongText], in: context)
        )

        let wrongField = DeidentificationAcknowledgment(
            fieldName: "answerText",
            matchedText: "445566"
        )
        XCTAssertThrowsError(
            try DIQuestionService.save(values, questionID: nil, acknowledging: [wrongField], in: context)
        )
    }

    func testEditedTextInvalidatesPriorAcknowledgment() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        values.background = "Protocol reference 445566 governs dosing."
        let acknowledgment = DeidentificationAcknowledgment(
            fieldName: "background",
            matchedText: "445566"
        )
        let question = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: [acknowledgment],
            in: context
        )

        values.background = "Protocol reference 778899 governs dosing."
        XCTAssertThrowsError(
            try DIQuestionService.save(
                values,
                questionID: question.id,
                acknowledging: [acknowledgment],
                in: context
            )
        ) { error in
            guard case let DIQuestionServiceError.identifierFindingsRequireReview(findings)? =
                error as? DIQuestionServiceError
            else {
                XCTFail("expected gate findings")
                return
            }
            XCTAssertEqual(findings.first?.matchedText, "778899")
        }
    }

    func testCitationTitleAndLocatorPassThroughGate() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        var citation = DICitationValues()
        citation.title = "Chart note for MRN 12345678"
        citation.locator = "Section 2"
        values.citations = [citation]

        XCTAssertThrowsError(
            try DIQuestionService.save(values, questionID: nil, acknowledging: [], in: context)
        ) { error in
            guard case let DIQuestionServiceError.identifierFindingsRequireReview(findings)? =
                error as? DIQuestionServiceError
            else {
                XCTFail("expected gate findings")
                return
            }
            XCTAssertEqual(findings.first?.fieldName, "citationTitle")
        }
    }

    // MARK: Citations

    func testCitationsSaveUpdateAndReplaceWithoutOrphans() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        var first = DICitationValues()
        first.tier = .primary
        first.title = "Case series on serotonin syndrome"
        first.locator = "Journal, 2024"
        values.citations = [first]

        let question = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: [],
            in: context
        )
        XCTAssertEqual(question.citations.count, 1)

        var replacement = DICitationValues()
        replacement.tier = .guideline
        replacement.title = "Practice guideline"
        replacement.locator = "2026 revision"
        values.citations = [replacement]
        _ = try DIQuestionService.save(
            values,
            questionID: question.id,
            acknowledging: [],
            in: context
        )

        XCTAssertEqual(question.citations.count, 1)
        XCTAssertEqual(question.citations.first?.tier, .guideline)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Citation>()).count, 1)
    }

    func testCitationValidationRejectsMissingTitleAndMultiline() {
        var missingTitle = DICitationValues()
        missingTitle.locator = "Somewhere"
        XCTAssertThrowsError(try DIQuestionService.validateCitations([missingTitle])) { error in
            XCTAssertEqual(error as? DIQuestionServiceError, .citationTitleRequired)
        }

        var multiline = DICitationValues()
        multiline.title = "Line one\nline two"
        XCTAssertThrowsError(try DIQuestionService.validateCitations([multiline])) { error in
            XCTAssertEqual(
                error as? DIQuestionServiceError,
                .citationFieldTooLong(limit: DIQuestionService.citationFieldCharacterLimit)
            )
        }
    }

    // MARK: Answering

    func testMarkAnsweredSetsWindowAndRecordsFirstIntervalChoice() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try AppConfigService.fetchOrCreate(in: context)

        let question = try DIQuestionService.save(
            cleanValues(),
            questionID: nil,
            acknowledging: [],
            in: context
        )
        let creation = question.createdAt
        let verifiedOn = creation.addingTimeInterval(3_600)

        try DIQuestionService.markAnswered(
            questionID: question.id,
            verifiedOn: verifiedOn,
            stalenessMonths: 6,
            in: context
        )

        XCTAssertNotNil(question.answeredAt)
        XCTAssertEqual(question.verifiedOn, verifiedOn)
        let expectedReview = Calendar.current.date(byAdding: .month, value: 6, to: verifiedOn)
        XCTAssertEqual(question.reviewAfter, expectedReview)
        XCTAssertEqual(question.verificationHistory, [creation, verifiedOn])

        let configuration = try XCTUnwrap(try AppConfigService.existing(in: context))
        XCTAssertEqual(configuration.stalenessIntervalMonths, 6)
    }

    func testMarkAnsweredRejectsVerificationBeforeCreation() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let question = try DIQuestionService.save(
            cleanValues(),
            questionID: nil,
            acknowledging: [],
            in: context
        )
        XCTAssertThrowsError(
            try DIQuestionService.markAnswered(
                questionID: question.id,
                verifiedOn: question.createdAt.addingTimeInterval(-60),
                stalenessMonths: 12,
                in: context
            )
        ) { error in
            XCTAssertEqual(
                error as? DIQuestionServiceError,
                .verificationMustFollowCreation
            )
        }
        XCTAssertNil(question.answeredAt)
    }

    // MARK: Guard-on-import readiness

    func testArchiveGateSurfacesPlantedIdentifier() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        values.background = "Protocol reference 445566 governs dosing."
        _ = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: [
                DeidentificationAcknowledgment(fieldName: "background", matchedText: "445566")
            ],
            in: context
        )

        let archive = try BackupService.makeArchive(from: context)
        let findings = DIQuestionService.gateFindings(forArchive: archive)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.matchedText, "445566")

        let cleanArchive = try BackupService.makeArchive(
            from: HippocratesStore.makeContainer(inMemory: true).mainContext
        )
        XCTAssertTrue(DIQuestionService.gateFindings(forArchive: cleanArchive).isEmpty)
    }

    // MARK: Backup parity

    func testBackupRoundTripWithDraftAndCitation() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        var values = cleanValues()
        var citation = DICitationValues()
        citation.tier = .primary
        citation.title = "Case series on serotonin syndrome"
        citation.locator = "Journal, 2024"
        citation.accessedDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        values.citations = [citation]
        _ = try DIQuestionService.save(values, questionID: nil, acknowledging: [], in: context)

        let exportDate = Date(timeIntervalSinceReferenceDate: 710_000_000)
        let archive = try BackupService.makeArchive(from: context, createdAt: exportDate)
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)
        let reexported = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )
        XCTAssertEqual(archive, reexported)
    }
}
