import Foundation

/// The 90-day backup reminder (I-011). It keys off the recorded
/// archive-generation timestamp only: a never-exported install shows no
/// reminder (nothing has "exceeded 90 days"), and generation is never
/// described as confirmed delivery.
enum BackupReminderPolicy {
    static let thresholdDays = 90

    static func shouldRemind(lastExportAt: Date?, now: Date) -> Bool {
        guard let lastExportAt else {
            return false
        }
        let threshold = Double(thresholdDays) * 86_400.0
        return now.timeIntervalSince(lastExportAt) >= threshold
    }
}
