import SwiftUI

/// A value option for a taxonomy picker. The capture and ledger screens hold
/// these snapshots and pass UUIDs back to the services; they never bind a live
/// model into a control.
struct PickerOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
}

enum AcceptanceDisplay {
    /// Plain display strings for the acceptance vocabulary. Raw enum values are
    /// persistence identifiers; these labels are presentation only.
    static func label(_ acceptance: Acceptance) -> String {
        switch acceptance {
        case .accepted:
            return "Accepted"
        case .rejected:
            return "Rejected"
        case .pending:
            return "Pending"
        case .notApplicable:
            return "Not applicable"
        }
    }

    /// The capture order presents the most common outcomes first. Pending is
    /// the honest default when the outcome is not yet known.
    static let captureOrder: [Acceptance] = [.accepted, .pending, .rejected, .notApplicable]
}
