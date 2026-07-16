import Foundation
import SwiftData

enum BackupError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case duplicateIdentifier(entity: String, id: UUID)
    case danglingReference(entity: String, id: UUID, field: String, referencedID: UUID)
    case invalidCostAvoidanceKey(String)
    case conflictingLegacyCostAvoidanceValue(typeID: UUID, typeValue: Int, configValue: Int)
    case invalidCostAvoidanceValue(entity: String, id: UUID, value: Int)
    case invalidMinutesSpentValue(interventionID: UUID, value: Int)
    case verificationHistoryDoesNotEndAtVerifiedOn(questionID: UUID)
    case verificationHistoryNotChronological(questionID: UUID)
    case reviewDateMustFollowVerification(questionID: UUID)
    case invalidStalenessIntervalMonths(Int)
    case multipleAppConfigs
    case destinationHasPendingChanges
    case destinationNotEmpty
}

/// ModelContext is main-actor isolated. Keeping store access in this service on
/// the main actor avoids passing @Model reference types across concurrency
/// domains. The returned BackupArchive is a Sendable value.
@MainActor
enum BackupService {
    static func makeArchive(
        from context: ModelContext,
        createdAt: Date = .now
    ) throws -> BackupArchive {
        let interventionTypes = try context.fetch(FetchDescriptor<InterventionType>())
        let drugClasses = try context.fetch(FetchDescriptor<DrugClass>())
        let serviceLines = try context.fetch(FetchDescriptor<ServiceLine>())
        let interventions = try context.fetch(FetchDescriptor<Intervention>())
        let questions = try context.fetch(FetchDescriptor<DIQuestion>())
        let citations = try context.fetch(FetchDescriptor<Citation>())
        let configuration: AppConfig?
        do {
            configuration = try AppConfigService.existing(in: context)
        } catch {
            if case AppConfigServiceError.multipleConfigurations = error {
                throw BackupError.multipleAppConfigs
            }
            throw error
        }

        let payload = BackupArchive.Payload(
            interventionTypes: interventionTypes
                .map {
                    .init(
                        id: $0.id,
                        label: $0.label,
                        defaultCostAvoidanceCents: $0.defaultCostAvoidanceCents,
                        isActive: $0.isActive,
                        sortOrder: $0.sortOrder
                    )
                }
                .sorted(by: idOrder),
            drugClasses: drugClasses
                .map { .init(id: $0.id, label: $0.label, isActive: $0.isActive, sortOrder: $0.sortOrder) }
                .sorted(by: idOrder),
            serviceLines: serviceLines
                .map { .init(id: $0.id, label: $0.label, isActive: $0.isActive, sortOrder: $0.sortOrder) }
                .sorted(by: idOrder),
            interventions: interventions
                .map {
                    .init(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        typeID: $0.type?.id,
                        drugClassID: $0.drugClass?.id,
                        serviceLineID: $0.serviceLine?.id,
                        acceptance: $0.acceptance,
                        costAvoidanceCents: $0.costAvoidanceCents,
                        minutesSpent: $0.minutesSpent,
                        diQuestionID: $0.diQuestion?.id
                    )
                }
                .sorted(by: idOrder),
            questions: questions
                .map {
                    .init(
                        id: $0.id,
                        createdAt: $0.createdAt,
                        answeredAt: $0.answeredAt,
                        questionText: $0.questionText,
                        background: $0.background,
                        answerText: $0.answerText,
                        searchStrategy: $0.searchStrategy,
                        requestorRole: $0.requestorRole,
                        questionClass: $0.questionClass,
                        urgency: $0.urgency,
                        verifiedOn: $0.verifiedOn,
                        reviewAfter: $0.reviewAfter,
                        didFollowUp: $0.didFollowUp,
                        tags: $0.tags,
                        verificationHistory: $0.verificationHistory
                    )
                }
                .sorted(by: idOrder),
            citations: citations
                .map {
                    .init(
                        id: $0.id,
                        questionID: $0.question?.id,
                        tier: $0.tier,
                        title: $0.title,
                        locator: $0.locator,
                        accessedDate: $0.accessedDate,
                        urlString: $0.urlString
                    )
                }
                .sorted(by: idOrder),
            appConfig: configuration.map {
                .init(
                    stalenessIntervalMonths: $0.stalenessIntervalMonths,
                    lastExportAt: $0.lastExportAt
                )
            }
        )

        let archive = BackupArchive(createdAt: createdAt, payload: payload)
        try validate(archive)
        return archive
    }

    /// Restores only into a fresh, empty context. `ModelContext.transaction`
    /// saves all pending work in that context, while rollback discards all of
    /// it. Refusing a dirty context prevents backup restore from committing or
    /// rolling back unrelated edits. Callers should create a dedicated context
    /// for restore, discard it after any thrown restore error, and never borrow
    /// one from an editing screen.
    ///
    /// The spec does not authorize merge or replacement semantics; guessing
    /// could duplicate or erase years of records. A future replacement UI
    /// requires an explicit product decision.
    static func restore(_ archive: BackupArchive, into context: ModelContext) throws {
        try validate(archive)
        guard !context.hasChanges else {
            throw BackupError.destinationHasPendingChanges
        }
        guard try isEmpty(context) else {
            throw BackupError.destinationNotEmpty
        }

        do {
            try context.transaction {
                if let configuration = archive.payload.appConfig {
                    _ = try AppConfigService.insertForRestore(
                        stalenessIntervalMonths: configuration.stalenessIntervalMonths,
                        lastExportAt: configuration.lastExportAt,
                        into: context
                    )
                }

                let typeByID = Dictionary(
                    uniqueKeysWithValues: archive.payload.interventionTypes.map { record in
                        let model = InterventionType(
                            id: record.id,
                            label: record.label,
                            defaultCostAvoidanceCents: record.defaultCostAvoidanceCents,
                            isActive: record.isActive,
                            sortOrder: record.sortOrder
                        )
                        context.insert(model)
                        return (record.id, model)
                    }
                )

                let drugClassByID = Dictionary(
                    uniqueKeysWithValues: archive.payload.drugClasses.map { record in
                        let model = DrugClass(
                            id: record.id,
                            label: record.label,
                            isActive: record.isActive,
                            sortOrder: record.sortOrder
                        )
                        context.insert(model)
                        return (record.id, model)
                    }
                )

                let serviceLineByID = Dictionary(
                    uniqueKeysWithValues: archive.payload.serviceLines.map { record in
                        let model = ServiceLine(
                            id: record.id,
                            label: record.label,
                            isActive: record.isActive,
                            sortOrder: record.sortOrder
                        )
                        context.insert(model)
                        return (record.id, model)
                    }
                )

                let questionByID = Dictionary(
                    uniqueKeysWithValues: archive.payload.questions.map { record in
                        let model = DIQuestion(
                            id: record.id,
                            createdAt: record.createdAt,
                            answeredAt: record.answeredAt,
                            questionText: record.questionText,
                            background: record.background,
                            answerText: record.answerText,
                            searchStrategy: record.searchStrategy,
                            requestorRole: record.requestorRole,
                            questionClass: record.questionClass,
                            urgency: record.urgency,
                            verifiedOn: record.verifiedOn,
                            reviewAfter: record.reviewAfter,
                            didFollowUp: record.didFollowUp,
                            tags: record.tags,
                            verificationHistory: record.verificationHistory
                        )
                        context.insert(model)
                        return (record.id, model)
                    }
                )

                for record in archive.payload.citations {
                    let model = Citation(
                        id: record.id,
                        question: record.questionID.flatMap { questionByID[$0] },
                        tier: record.tier,
                        title: record.title,
                        locator: record.locator,
                        accessedDate: record.accessedDate,
                        urlString: record.urlString
                    )
                    context.insert(model)
                }

                for record in archive.payload.interventions {
                    let model = Intervention(
                        id: record.id,
                        timestamp: record.timestamp,
                        type: record.typeID.flatMap { typeByID[$0] },
                        drugClass: record.drugClassID.flatMap { drugClassByID[$0] },
                        serviceLine: record.serviceLineID.flatMap { serviceLineByID[$0] },
                        acceptance: record.acceptance,
                        costAvoidanceCents: record.costAvoidanceCents,
                        minutesSpent: record.minutesSpent,
                        diQuestion: record.diQuestionID.flatMap { questionByID[$0] }
                    )
                    context.insert(model)
                }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    static func validate(_ archive: BackupArchive) throws {
        guard archive.formatVersion == BackupArchive.currentFormatVersion else {
            throw BackupError.unsupportedFormatVersion(archive.formatVersion)
        }

        let typeIDs = try uniqueIDs(
            archive.payload.interventionTypes,
            entity: "InterventionType",
            id: \.id
        )
        let drugClassIDs = try uniqueIDs(
            archive.payload.drugClasses,
            entity: "DrugClass",
            id: \.id
        )
        let serviceLineIDs = try uniqueIDs(
            archive.payload.serviceLines,
            entity: "ServiceLine",
            id: \.id
        )
        let questionIDs = try uniqueIDs(
            archive.payload.questions,
            entity: "DIQuestion",
            id: \.id
        )
        _ = try uniqueIDs(archive.payload.citations, entity: "Citation", id: \.id)
        _ = try uniqueIDs(archive.payload.interventions, entity: "Intervention", id: \.id)

        for type in archive.payload.interventionTypes {
            try validateCost(
                type.defaultCostAvoidanceCents,
                entity: "InterventionType",
                id: type.id
            )
        }

        for intervention in archive.payload.interventions {
            try validateCost(
                intervention.costAvoidanceCents,
                entity: "Intervention",
                id: intervention.id
            )
            if let minutesSpent = intervention.minutesSpent,
               minutesSpent < 0 {
                throw BackupError.invalidMinutesSpentValue(
                    interventionID: intervention.id,
                    value: minutesSpent
                )
            }
        }

        for question in archive.payload.questions
        where question.verificationHistory.last != question.verifiedOn {
            throw BackupError.verificationHistoryDoesNotEndAtVerifiedOn(questionID: question.id)
        }

        for question in archive.payload.questions
        where !zip(
            question.verificationHistory,
            question.verificationHistory.dropFirst()
        ).allSatisfy({ pair in pair.0 < pair.1 }) {
            throw BackupError.verificationHistoryNotChronological(questionID: question.id)
        }

        for question in archive.payload.questions
        where question.reviewAfter <= question.verifiedOn {
            throw BackupError.reviewDateMustFollowVerification(questionID: question.id)
        }

        for citation in archive.payload.citations {
            try requireReference(
                citation.questionID,
                in: questionIDs,
                entity: "Citation",
                id: citation.id,
                field: "questionID"
            )
        }

        for intervention in archive.payload.interventions {
            try requireReference(
                intervention.typeID,
                in: typeIDs,
                entity: "Intervention",
                id: intervention.id,
                field: "typeID"
            )
            try requireReference(
                intervention.drugClassID,
                in: drugClassIDs,
                entity: "Intervention",
                id: intervention.id,
                field: "drugClassID"
            )
            try requireReference(
                intervention.serviceLineID,
                in: serviceLineIDs,
                entity: "Intervention",
                id: intervention.id,
                field: "serviceLineID"
            )
            try requireReference(
                intervention.diQuestionID,
                in: questionIDs,
                entity: "Intervention",
                id: intervention.id,
                field: "diQuestionID"
            )
        }

        if let months = archive.payload.appConfig?.stalenessIntervalMonths,
           months <= 0 {
            throw BackupError.invalidStalenessIntervalMonths(months)
        }
    }

    private static func validateCost(
        _ value: Int?,
        entity: String,
        id: UUID
    ) throws {
        if let value, value < 0 {
            throw BackupError.invalidCostAvoidanceValue(
                entity: entity,
                id: id,
                value: value
            )
        }
    }

    private static func isEmpty(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<InterventionType>()) == 0
            && context.fetchCount(FetchDescriptor<DrugClass>()) == 0
            && context.fetchCount(FetchDescriptor<ServiceLine>()) == 0
            && context.fetchCount(FetchDescriptor<Intervention>()) == 0
            && context.fetchCount(FetchDescriptor<DIQuestion>()) == 0
            && context.fetchCount(FetchDescriptor<Citation>()) == 0
            && context.fetchCount(FetchDescriptor<AppConfig>()) == 0
    }

    private static func uniqueIDs<Record>(
        _ records: [Record],
        entity: String,
        id: KeyPath<Record, UUID>
    ) throws -> Set<UUID> {
        var ids: Set<UUID> = []
        for record in records {
            let recordID = record[keyPath: id]
            guard ids.insert(recordID).inserted else {
                throw BackupError.duplicateIdentifier(entity: entity, id: recordID)
            }
        }
        return ids
    }

    private static func requireReference(
        _ referencedID: UUID?,
        in validIDs: Set<UUID>,
        entity: String,
        id: UUID,
        field: String
    ) throws {
        guard let referencedID else { return }
        guard validIDs.contains(referencedID) else {
            throw BackupError.danglingReference(
                entity: entity,
                id: id,
                field: field,
                referencedID: referencedID
            )
        }
    }

    private static func idOrder<Record>(
        _ left: Record,
        _ right: Record
    ) -> Bool where Record: Identifiable, Record.ID == UUID {
        left.id.uuidString < right.id.uuidString
    }
}

extension BackupArchive.InterventionTypeRecord: Identifiable {}
extension BackupArchive.DrugClassRecord: Identifiable {}
extension BackupArchive.ServiceLineRecord: Identifiable {}
extension BackupArchive.InterventionRecord: Identifiable {}
extension BackupArchive.DIQuestionRecord: Identifiable {}
extension BackupArchive.CitationRecord: Identifiable {}
