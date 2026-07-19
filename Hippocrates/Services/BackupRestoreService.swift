import Foundation
import SwiftData

enum BackupRestoreError: Error, Equatable {
    case malformedFile
    /// The archive contains free text that looks like patient identifiers.
    /// Import is refused before any store mutation; no per-finding override is
    /// offered for a bulk import (the de-identification gate has no safe way to
    /// bulk-acknowledge someone else's export).
    case identifierFindingsPresent([DeidentificationFinding])
    case destinationNotEmpty
    case invalidArchive
}

/// Restore ingress (I-003, I-010). Decode, then graph/domain validation, then
/// the de-identification gate, and only then mutation into a verified-empty
/// pre-bootstrap store. Every failure happens before any record is inserted.
@MainActor
enum BackupRestoreService {
    /// Runs the full gauntlet on app-owned Data from the reviewed import
    /// adapter and restores into `context`. `context` must be empty
    /// (pre-bootstrap); a populated store is refused (v1 has no destructive
    /// replacement path).
    static func restore(from data: Data, into context: ModelContext) throws {
        let archive: BackupArchive
        do {
            archive = try BackupCodec.decode(data)
        } catch {
            throw BackupRestoreError.malformedFile
        }

        // Validate the graph and domain invariants before scanning or mutating.
        do {
            try BackupService.validate(archive)
        } catch {
            throw BackupRestoreError.invalidArchive
        }

        // The de-identification gate: refuse an archive whose DI free text,
        // tags, or citation metadata look like identifiers. This is the same
        // scan the editor uses; import cannot bypass it.
        let findings = DIQuestionService.gateFindings(forArchive: archive)
        guard findings.isEmpty else {
            throw BackupRestoreError.identifierFindingsPresent(findings)
        }

        do {
            try BackupService.restore(archive, into: context)
        } catch BackupError.destinationNotEmpty {
            throw BackupRestoreError.destinationNotEmpty
        } catch BackupError.destinationHasPendingChanges {
            throw BackupRestoreError.destinationNotEmpty
        }
    }
}
