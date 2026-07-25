import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

/// One production-backed regression path for the core offline V1 service seams:
/// configuration, ledger, DI lifecycle, operational exports, backup, and
/// pristine-store restore. Narrow subsystem tests still own their edge matrices;
/// this suite proves those seams remain compatible with one another.
@MainActor
final class V1GoldenJourneyTests: XCTestCase {
    private struct StoreCounts: Equatable, Sendable {
        let interventionTypes: Int
        let drugClasses: Int
        let serviceLines: Int
        let interventions: Int
        let questions: Int
        let citations: Int
        let appConfigs: Int

        static let zero = StoreCounts(
            interventionTypes: 0,
            drugClasses: 0,
            serviceLines: 0,
            interventions: 0,
            questions: 0,
            citations: 0,
            appConfigs: 0
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    func testOfflineV1LifecycleSurvivesProductionBackupRestore() throws {
        // 1-2. A new production container is pristine and follows the supported
        // first-run configuration and explicit starter-taxonomy path.
        let sourceContainer = try HippocratesStore.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        XCTAssertEqual(try storeCounts(in: sourceContext), .zero)
        XCTAssertNil(try AppConfigService.existing(in: sourceContext))
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: false,
                activeInterventionTypeCount: 0,
                activeDrugClassCount: 0
            ),
            .firstRun
        )

        let configuration = try AppConfigService.fetchOrCreate(in: sourceContext)
        XCTAssertNil(configuration.stalenessIntervalMonths)
        XCTAssertNil(configuration.lastExportAt)

        let selectedTypeLabels = Array(StarterTaxonomy.interventionTypeLabels.prefix(1))
        let selectedClassLabels = Array(StarterTaxonomy.drugClassLabels.prefix(2))
        let initialClassLabel = try XCTUnwrap(selectedClassLabels.first)
        let editedClassLabel = try XCTUnwrap(selectedClassLabels.last)
        let selectedLineLabels = Array(StarterTaxonomy.serviceLineLabels.prefix(1))
        try TaxonomyService.seedStarterTaxonomies(
            interventionTypeLabels: selectedTypeLabels,
            drugClassLabels: selectedClassLabels,
            serviceLineLabels: selectedLineLabels,
            in: sourceContext
        )

        let starterTypes = try TaxonomyService.allInterventionTypes(in: sourceContext)
        let starterClasses = try TaxonomyService.allDrugClasses(in: sourceContext)
        let starterLines = try TaxonomyService.allServiceLines(in: sourceContext)
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: true,
                activeInterventionTypeCount: starterTypes.filter(\.isActive).count,
                activeDrugClassCount: starterClasses.filter(\.isActive).count
            ),
            .captureReady
        )

        let initialType = try XCTUnwrap(starterTypes.first)
        let initialClass = try XCTUnwrap(
            starterClasses.first { $0.label == initialClassLabel }
        )
        let editedClass = try XCTUnwrap(
            starterClasses.first { $0.label == editedClassLabel }
        )
        let serviceLine = try XCTUnwrap(starterLines.first)
        let editedType = try TaxonomyService.addInterventionType(
            label: "=Synthetic optimization",
            defaultCostAvoidanceCents: 1_500,
            in: sourceContext
        )

        // 3-4 and 15. Invalid capture and edit requests fail before mutation;
        // the supported pending-resolution and structured-edit paths then
        // produce one de-identified intervention with no narrative surface.
        let beforeInvalidCapture = try storeCounts(in: sourceContext)
        XCTAssertThrowsError(
            try InterventionCaptureService.record(
                CaptureDraft(
                    typeID: initialType.id,
                    drugClassID: initialClass.id,
                    acceptance: .pending,
                    minutesSpent: -1
                ),
                at: Date(timeIntervalSince1970: 1_768_478_400),
                in: sourceContext
            )
        ) { error in
            XCTAssertEqual(error as? InterventionCaptureError, .negativeMinutes(-1))
        }
        XCTAssertEqual(try storeCounts(in: sourceContext), beforeInvalidCapture)
        XCTAssertFalse(sourceContext.hasChanges)

        let interventionTimestamp = Date(timeIntervalSince1970: 1_768_478_400)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(
                typeID: initialType.id,
                drugClassID: initialClass.id,
                acceptance: .pending
            ),
            at: interventionTimestamp,
            in: sourceContext
        )
        try InterventionLedgerService.setAcceptance(
            .accepted,
            forInterventionID: intervention.id,
            in: sourceContext
        )
        try InterventionLedgerService.apply(
            InterventionEdit(
                typeID: editedType.id,
                drugClassID: editedClass.id,
                serviceLineID: serviceLine.id,
                acceptance: .accepted,
                minutesSpent: 17,
                costAvoidanceCents: 2_500
            ),
            toInterventionID: intervention.id,
            in: sourceContext
        )

        let editedIntervention = try XCTUnwrap(
            try InterventionLedgerService.recent(in: sourceContext).first
        )
        XCTAssertEqual(editedIntervention.typeID, editedType.id)
        XCTAssertEqual(editedIntervention.drugClassID, editedClass.id)
        XCTAssertEqual(editedIntervention.serviceLineID, serviceLine.id)
        XCTAssertEqual(editedIntervention.acceptance, .accepted)
        XCTAssertEqual(editedIntervention.minutesSpent, 17)
        XCTAssertEqual(editedIntervention.costAvoidanceCents, 2_500)

        XCTAssertThrowsError(
            try InterventionLedgerService.apply(
                InterventionEdit(
                    typeID: initialType.id,
                    drugClassID: initialClass.id,
                    serviceLineID: nil,
                    acceptance: .rejected,
                    minutesSpent: -5,
                    costAvoidanceCents: nil
                ),
                toInterventionID: intervention.id,
                in: sourceContext
            )
        ) { error in
            XCTAssertEqual(error as? InterventionLedgerError, .negativeMinutes(-5))
        }
        XCTAssertEqual(
            try InterventionLedgerService.recent(in: sourceContext).first,
            editedIntervention
        )
        XCTAssertFalse(sourceContext.hasChanges)

        // 5-7. The DI item begins as a linked draft, is edited only after the
        // de-identification gate, becomes answered, and a later refetch exposes freshness
        // derived from its durable dates rather than a stored color.
        let linkedDraft = try DIQuestionService.createLinkedDraft(
            interventionID: intervention.id,
            in: sourceContext
        )
        XCTAssertNil(linkedDraft.answeredAt)
        XCTAssertEqual(
            FreshnessPolicy.state(
                answeredAt: linkedDraft.answeredAt,
                verifiedOn: linkedDraft.verifiedOn,
                reviewAfter: linkedDraft.reviewAfter,
                now: .distantFuture
            ),
            .draft
        )
        XCTAssertEqual(
            try DIQuestionService.linkedInterventions(
                of: linkedDraft.id,
                in: sourceContext
            ).map(\.id),
            [intervention.id]
        )
        XCTAssertEqual(
            try InterventionLedgerService.recent(in: sourceContext).first?.diQuestionID,
            linkedDraft.id
        )

        var values = DIDraftValues()
        values.questionText = "Which source types support this synthetic compatibility review?"
        values.background = "Synthetic teaching fixture without person, encounter, room, or institution details."
        values.answerText = "This fixture records the source-review process only."
        values.searchStrategy = "Primary publication and product labeling."
        values.requestorRole = .pharmacist
        values.questionClass = .compatibility
        values.urgency = .routine
        values.didFollowUp = true
        let citationID = try XCTUnwrap(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        )
        values.citations = [
            DICitationValues(
                id: citationID,
                tier: .primary,
                title: "Synthetic source review",
                locator: "Appendix A",
                accessedDate: Date(timeIntervalSince1970: 1_768_435_200),
                urlString: nil
            )
        ]
        XCTAssertTrue(DIQuestionService.gateFindings(for: values).isEmpty)
        let savedQuestion = try DIQuestionService.save(
            values,
            questionID: linkedDraft.id,
            acknowledging: [],
            in: sourceContext
        )
        XCTAssertEqual(DIQuestionService.values(of: savedQuestion), values)
        XCTAssertEqual(savedQuestion.citations.count, 1)

        // 14-15. Synthetic patient-identifying input is rejected for both a
        // prospective record and an existing record before either store shape
        // or already-saved values can change.
        var prohibitedValues = values
        let prohibitedBackground = "Synthetic prohibited fixture: MRN 12345678."
        prohibitedValues.background = prohibitedBackground
        let beforeProhibitedSave = try storeCounts(in: sourceContext)
        XCTAssertThrowsError(
            try DIQuestionService.save(
                prohibitedValues,
                questionID: nil,
                acknowledging: [],
                in: sourceContext
            )
        ) { error in
            guard
                let serviceError = error as? DIQuestionServiceError,
                case let .identifierFindingsRequireReview(findings) = serviceError
            else {
                XCTFail("Expected the de-identification gate to reject the synthetic identifier.")
                return
            }
            XCTAssertTrue(findings.contains { $0.category == .medicalRecordNumber })
        }
        XCTAssertEqual(try storeCounts(in: sourceContext), beforeProhibitedSave)
        XCTAssertFalse(sourceContext.hasChanges)

        XCTAssertThrowsError(
            try DIQuestionService.save(
                prohibitedValues,
                questionID: savedQuestion.id,
                acknowledging: [],
                in: sourceContext
            )
        ) { error in
            guard
                let serviceError = error as? DIQuestionServiceError,
                case let .identifierFindingsRequireReview(findings) = serviceError
            else {
                XCTFail("Expected the de-identification gate to reject the existing record.")
                return
            }
            XCTAssertTrue(findings.contains { $0.category == .medicalRecordNumber })
        }
        let unchangedQuestion = try XCTUnwrap(
            try DIQuestionService.question(savedQuestion.id, in: sourceContext)
        )
        XCTAssertEqual(DIQuestionService.values(of: unchangedQuestion), values)
        XCTAssertEqual(try storeCounts(in: sourceContext), beforeProhibitedSave)
        XCTAssertFalse(sourceContext.hasChanges)

        let verifiedOn = savedQuestion.createdAt.addingTimeInterval(1)
        try DIQuestionService.markAnswered(
            questionID: savedQuestion.id,
            verifiedOn: verifiedOn,
            stalenessMonths: 6,
            in: sourceContext
        )
        let answeredQuestion = try XCTUnwrap(
            try DIQuestionService.question(savedQuestion.id, in: sourceContext)
        )
        XCTAssertNotNil(answeredQuestion.answeredAt)
        XCTAssertEqual(
            try AppConfigService.existing(in: sourceContext)?.stalenessIntervalMonths,
            6
        )

        let reviewInterval = answeredQuestion.reviewAfter.timeIntervalSince(
            answeredQuestion.verifiedOn
        )
        XCTAssertGreaterThan(reviewInterval, 0)
        XCTAssertEqual(
            freshness(of: answeredQuestion, now: answeredQuestion.reviewAfter),
            .green
        )
        XCTAssertEqual(
            freshness(
                of: answeredQuestion,
                now: answeredQuestion.reviewAfter.addingTimeInterval(1)
            ),
            .amber
        )
        let staleEvaluationDate = answeredQuestion.reviewAfter
            .addingTimeInterval(reviewInterval)
            .addingTimeInterval(1)
        let refetchedQuestion = try XCTUnwrap(
            try DIQuestionService.question(answeredQuestion.id, in: sourceContext)
        )
        let refetchedFreshness = freshness(of: refetchedQuestion, now: staleEvaluationDate)
        XCTAssertEqual(refetchedFreshness, .red)
        XCTAssertEqual(
            DIOpenPolicy.destination(for: refetchedFreshness),
            .stalenessInterstitial
        )
        XCTAssertEqual(DIDisplay.badgeText(.red), "Out of date")

        // 8-9. Snapshot through the production service, aggregate with an
        // explicit locale-independent calendar, and require exact RFC 4180 CSV
        // logical content including formula-cell neutralization.
        let summaryRange = SummaryDateRange(start: .distantPast, end: .distantFuture)
        let rowsBeforeBackup = try SummarySnapshotService.rows(
            in: summaryRange,
            from: sourceContext
        )
        let summaryBeforeBackup = SummaryEngine.statistics(
            for: rowsBeforeBackup,
            in: summaryRange,
            calendar: utcCalendar
        )
        XCTAssertEqual(summaryBeforeBackup.totalCount, 1)
        XCTAssertEqual(summaryBeforeBackup.acceptance.accepted, 1)
        XCTAssertEqual(summaryBeforeBackup.acceptance.resolvedDenominator, 1)
        XCTAssertEqual(summaryBeforeBackup.acceptance.ratePermille, 1_000)
        XCTAssertEqual(summaryBeforeBackup.costTotalCents, 2_500)
        XCTAssertEqual(summaryBeforeBackup.minutesTotal, 17)
        XCTAssertEqual(summaryBeforeBackup.countsByType, [
            LabelCount(label: "=Synthetic optimization", count: 1)
        ])
        XCTAssertEqual(summaryBeforeBackup.topDrugClasses, [
            LabelCount(label: editedClass.label, count: 1)
        ])
        XCTAssertEqual(summaryBeforeBackup.serviceLineBreakdown, [
            LabelCount(label: serviceLine.label, count: 1)
        ])

        let csvBeforeBackup = InterventionCSV.document(rows: rowsBeforeBackup)
        let expectedCSV = InterventionCSV.header
            + "\r\n"
            + "2026-01-15T12:00:00Z,'=Synthetic optimization,"
            + editedClass.label
            + ","
            + serviceLine.label
            + ",accepted,2500,17\r\n"
        XCTAssertEqual(csvBeforeBackup, expectedCSV)

        // 16 and 18. Exercise the shipped stateless calculation and result
        // lifecycle while proving that a live input/result session cannot alter
        // the production archive or become a durable clinical record.
        let logicalArchiveDate = Date(timeIntervalSince1970: 1_800_000_000)
        try BackupExportService.recordBackupCreated(
            at: Date(timeIntervalSince1970: 1_735_689_600),
            in: sourceContext
        )
        let archiveBeforeRXcalc = try BackupService.makeArchive(
            from: sourceContext,
            createdAt: logicalArchiveDate
        )
        var resultSession = RXResultSession<CreatinineClearanceResult>()
        let calculation = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            ),
            calculatedAt: Date(timeIntervalSince1970: 1_768_435_200)
        )
        resultSession.publish(calculation)
        XCTAssertEqual(calculation.millilitersPerMinute, 87.5, accuracy: 0.000_000_1)
        XCTAssertTrue(calculation.provenance.humanReviewRequired)
        XCTAssertFalse(calculation.provenance.isAutonomousClinicalRecommendation)
        XCTAssertTrue(resultSession.mayCopyOrExportAsCurrent)
        XCTAssertNotNil(
            RXResultExportGate.currentEngineeringSummary(
                currency: resultSession.currency,
                formulaIdentifiers: calculation.provenance.formulaIdentifiers,
                outputDescription: "87.5 mL/min",
                reviewStatusTitle: calculation.provenance.sourceReviewStatusTitle,
                calculatedAtDescription: "fixed golden-journey time"
            )
        )
        XCTAssertEqual(
            try BackupService.makeArchive(
                from: sourceContext,
                createdAt: logicalArchiveDate
            ),
            archiveBeforeRXcalc
        )

        // 10. Use the same production data exporter and current codec used by
        // the share flow. The timestamp is event metadata; payload equality is
        // the deterministic logical backup contract.
        let backupData = try BackupExportService.makeBackupData(in: sourceContext)
        let backupArchive = try BackupCodec.decode(backupData)
        XCTAssertEqual(backupArchive.formatVersion, BackupArchive.currentFormatVersion)
        XCTAssertEqual(backupArchive.payload, archiveBeforeRXcalc.payload)
        XCTAssertEqual(backupArchive.payload.appConfig?.stalenessIntervalMonths, 6)
        XCTAssertEqual(
            backupArchive.payload.appConfig?.lastExportAt,
            Date(timeIntervalSince1970: 1_735_689_600)
        )
        XCTAssertEqual(
            try storeCounts(in: sourceContext),
            StoreCounts(
                interventionTypes: 2,
                drugClasses: 2,
                serviceLines: 1,
                interventions: 1,
                questions: 1,
                citations: 1,
                appConfigs: 1
            )
        )

        let backupText = String(decoding: backupData, as: UTF8.self)
        XCTAssertFalse(backupText.contains(prohibitedBackground))
        XCTAssertFalse(backupText.contains(CreatinineClearanceCalculator.formulaIdentifier))
        XCTAssertFalse(backupText.contains("\"freshness\""))
        XCTAssertFalse(backupText.contains("\"ratePermille\""))
        XCTAssertFalse(backupText.contains("\"hasCompletedFirstRun\""))
        XCTAssertFalse(backupText.contains("\"summaryRangeChoice\""))

        resultSession.invalidate()
        XCTAssertTrue(resultSession.isStale)
        XCTAssertFalse(resultSession.mayCopyOrExportAsCurrent)
        XCTAssertNil(
            RXResultExportGate.currentEngineeringSummary(
                currency: resultSession.currency,
                formulaIdentifiers: calculation.provenance.formulaIdentifiers,
                outputDescription: "87.5 mL/min",
                reviewStatusTitle: calculation.provenance.sourceReviewStatusTitle,
                calculatedAtDescription: "fixed golden-journey time"
            )
        )
        resultSession.abandonSurface()
        XCTAssertEqual(resultSession.currency, .none)
        XCTAssertNil(resultSession.value)

        // 11-13 and 17. Restore through the production ingress service into a
        // separate pristine production container, then require exact logical
        // archive equality and identical operational exports.
        let restoredContainer = try HippocratesStore.makeContainer(inMemory: true)
        let restoredContext = restoredContainer.mainContext
        XCTAssertEqual(try storeCounts(in: restoredContext), .zero)
        XCTAssertNil(try AppConfigService.existing(in: restoredContext))
        try BackupRestoreService.restore(from: backupData, into: restoredContext)
        XCTAssertFalse(restoredContext.hasChanges)

        let restoredArchive = try BackupService.makeArchive(
            from: restoredContext,
            createdAt: backupArchive.createdAt
        )
        XCTAssertEqual(restoredArchive, backupArchive)

        let rowsAfterRestore = try SummarySnapshotService.rows(
            in: summaryRange,
            from: restoredContext
        )
        let summaryAfterRestore = SummaryEngine.statistics(
            for: rowsAfterRestore,
            in: summaryRange,
            calendar: utcCalendar
        )
        XCTAssertEqual(summaryAfterRestore, summaryBeforeBackup)
        XCTAssertEqual(InterventionCSV.document(rows: rowsAfterRestore), csvBeforeBackup)

        let restoredQuestion = try XCTUnwrap(
            try DIQuestionService.question(savedQuestion.id, in: restoredContext)
        )
        XCTAssertEqual(freshness(of: restoredQuestion, now: staleEvaluationDate), .red)
        XCTAssertEqual(
            try DIQuestionService.linkedInterventions(
                of: restoredQuestion.id,
                in: restoredContext
            ).map(\.id),
            [intervention.id]
        )
        XCTAssertEqual(
            try InterventionLedgerService.recent(in: restoredContext).first?.diQuestionID,
            restoredQuestion.id
        )

        let restoredConfiguration = try XCTUnwrap(
            try AppConfigService.existing(in: restoredContext)
        )
        XCTAssertEqual(restoredConfiguration.stalenessIntervalMonths, 6)
        XCTAssertEqual(
            restoredConfiguration.lastExportAt,
            Date(timeIntervalSince1970: 1_735_689_600)
        )
        let freshResultSessionAfterRestore = RXResultSession<CreatinineClearanceResult>()
        XCTAssertEqual(freshResultSessionAfterRestore.currency, .none)
        XCTAssertNil(freshResultSessionAfterRestore.value)

        let historyCountBeforeReverify = restoredQuestion.verificationHistory.count
        let reverifiedOn = staleEvaluationDate.addingTimeInterval(60)
        try DIQuestionService.reverifyPreservingWindow(
            questionID: restoredQuestion.id,
            on: reverifiedOn,
            in: restoredContext
        )
        let reverifiedQuestion = try XCTUnwrap(
            try DIQuestionService.question(restoredQuestion.id, in: restoredContext)
        )
        XCTAssertEqual(
            reverifiedQuestion.verificationHistory.count,
            historyCountBeforeReverify + 1
        )
        let reverifiedFreshness = freshness(of: reverifiedQuestion, now: reverifiedOn)
        XCTAssertEqual(reverifiedFreshness, .green)
        XCTAssertEqual(DIOpenPolicy.destination(for: reverifiedFreshness), .editor)
        XCTAssertEqual(
            reverifiedQuestion.reviewAfter.timeIntervalSince(reverifiedOn),
            reviewInterval,
            accuracy: 0.5
        )
        XCTAssertFalse(restoredContext.hasChanges)
    }

    private func freshness(of question: DIQuestion, now: Date) -> FreshnessState {
        FreshnessPolicy.state(
            answeredAt: question.answeredAt,
            verifiedOn: question.verifiedOn,
            reviewAfter: question.reviewAfter,
            now: now
        )
    }

    private func storeCounts(in context: ModelContext) throws -> StoreCounts {
        StoreCounts(
            interventionTypes: try context.fetchCount(FetchDescriptor<InterventionType>()),
            drugClasses: try context.fetchCount(FetchDescriptor<DrugClass>()),
            serviceLines: try context.fetchCount(FetchDescriptor<ServiceLine>()),
            interventions: try context.fetchCount(FetchDescriptor<Intervention>()),
            questions: try context.fetchCount(FetchDescriptor<DIQuestion>()),
            citations: try context.fetchCount(FetchDescriptor<Citation>()),
            appConfigs: try context.fetchCount(FetchDescriptor<AppConfig>())
        )
    }
}
