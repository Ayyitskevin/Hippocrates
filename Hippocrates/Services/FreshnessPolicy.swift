import Foundation

/// The four DI freshness states. Freshness is never stored: every surface
/// computes it from the same durable dates through this one policy, so a
/// search row and a detail view can never disagree.
enum FreshnessState: Equatable, Sendable {
    case draft
    case green
    case amber
    case red
}

/// Pure freshness computation (A-006). A record with no answer is a draft
/// before any color; green lasts through `reviewAfter`; amber begins after
/// it; red begins after one additional per-record `reviewAfter - verifiedOn`
/// interval. Changing the app default never moves an older record's
/// boundaries, because both boundaries derive from the record's own dates.
enum FreshnessPolicy {
    static func state(
        answeredAt: Date?,
        verifiedOn: Date,
        reviewAfter: Date,
        now: Date
    ) -> FreshnessState {
        guard answeredAt != nil else {
            return .draft
        }
        // Save and import validation reject reviewAfter <= verifiedOn, so a
        // nonpositive interval is unreachable from persisted data. Red is the
        // fail-safe display if one ever appears, never a manufactured green.
        let interval = reviewAfter.timeIntervalSince(verifiedOn)
        guard interval > 0 else {
            return .red
        }
        if now <= reviewAfter {
            return .green
        }
        let redBegins = reviewAfter.addingTimeInterval(interval)
        if now <= redBegins {
            return .amber
        }
        return .red
    }
}
