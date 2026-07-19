import Foundation
import SwiftData

/// The full-backup flow. Generation produces app-owned bytes; recording the
/// event is the one caller of the I-011 export timestamp. Summary and
/// portfolio exports never pass through here.
@MainActor
enum BackupExportService {
    static func makeBackupData(in context: ModelContext) throws -> Data {
        try BackupCodec.encode(BackupService.makeArchive(from: context))
    }

    /// I-011: an archive was successfully generated and handed to the share
    /// sheet. This says nothing about delivery, and the reminder copy must
    /// never claim it does.
    static func recordBackupCreated(
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard let configuration = try AppConfigService.existing(in: context) else {
            return
        }
        AppConfigService.setLastExportAt(date, on: configuration)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func lastExportAt(in context: ModelContext) throws -> Date? {
        try AppConfigService.existing(in: context)?.lastExportAt
    }
}
