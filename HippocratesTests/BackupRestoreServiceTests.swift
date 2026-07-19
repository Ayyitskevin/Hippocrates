import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class BackupRestoreServiceTests: XCTestCase {
    private func populatedArchiveData(withIdentifierInBackground identifier: String?) throws -> Data {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try AppConfigService.fetchOrCreate(in: context)
        let type = try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .accepted),
            in: context
        )

        var values = DIDraftValues()
        values.questionText = "Is linezolid safe with sertraline?"
        values.answerText = "Monitor for serotonin syndrome."
        if let identifier {
            values.background = identifier
        }
        // Acknowledge any planted identifier so it persists into the archive;
        // the restore gate must catch it independently on import.
        let acknowledgments = identifier.map {
            [DeidentificationAcknowledgment(fieldName: "background", matchedText: extractedToken($0))]
        } ?? []
        _ = try DIQuestionService.save(
            values,
            questionID: nil,
            acknowledging: acknowledgments,
            in: context
        )

        return try BackupExportService.makeBackupData(in: context)
    }

    /// The exact matched token the scanner reports for a planted MRN phrase,
    /// so the source-store save can be acknowledged past its own gate.
    private func extractedToken(_ text: String) -> String {
        DeidentificationScanner.findings(fieldName: "background", text: text).first?.matchedText ?? text
    }

    // MARK: Clean restore

    func testCleanBackupRestoresIntoEmptyStore() throws {
        let data = try populatedArchiveData(withIdentifierInBackground: nil)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let context = destination.mainContext
        try BackupRestoreService.restore(from: data, into: context)

        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 1)
        XCTAssertEqual(try DIQuestionService.allQuestions(in: context).count, 1)
        XCTAssertEqual(try InterventionLedgerService.recent(in: context).count, 1)
    }

    // MARK: The gate on import

    func testRestoreRefusesArchiveWithIdentifiersAndMutatesNothing() throws {
        let data = try populatedArchiveData(
            withIdentifierInBackground: "Patient MRN: 12345678 on therapy."
        )

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let context = destination.mainContext
        XCTAssertThrowsError(try BackupRestoreService.restore(from: data, into: context)) { error in
            guard case let BackupRestoreError.identifierFindingsPresent(findings)? =
                error as? BackupRestoreError
            else {
                XCTFail("expected identifier findings")
                return
            }
            XCTAssertFalse(findings.isEmpty)
            XCTAssertTrue(findings.contains { $0.category == .medicalRecordNumber })
        }
        // Nothing was inserted: the gate runs before restore mutation.
        XCTAssertEqual(try DIQuestionService.allQuestions(in: context).count, 0)
        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    // MARK: Malformed input

    func testRestoreRejectsMalformedData() throws {
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let context = destination.mainContext
        XCTAssertThrowsError(
            try BackupRestoreService.restore(from: Data("not a backup".utf8), into: context)
        ) { error in
            XCTAssertEqual(error as? BackupRestoreError, .malformedFile)
        }
        XCTAssertFalse(context.hasChanges)
    }

    // MARK: Non-empty destination

    func testRestoreRefusesPopulatedDestination() throws {
        let data = try populatedArchiveData(withIdentifierInBackground: nil)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let context = destination.mainContext
        try TaxonomyService.addDrugClass(label: "Existing", in: context)

        XCTAssertThrowsError(try BackupRestoreService.restore(from: data, into: context)) { error in
            XCTAssertEqual(error as? BackupRestoreError, .destinationNotEmpty)
        }
    }
}
