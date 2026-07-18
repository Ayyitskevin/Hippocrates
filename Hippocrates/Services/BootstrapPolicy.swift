import Foundation

/// I-012: the launch decision is a pure function of the recorded onboarding
/// choice and the active taxonomy counts, so the same predicate drives the
/// first-run gate, the capture screen, and tests without duplicated logic.
enum BootstrapState: Equatable, Sendable {
    /// The one-time first-run flow has never been completed on this
    /// installation. The gate shows the responsibility notice and the
    /// starter-taxonomy offer before anything else.
    case firstRun

    /// First-run completed, but capture prerequisites are missing. This is the
    /// intentionally-minimal state I-012 distinguishes from never-configured:
    /// the user declined or removed taxonomy rows, so the app routes to
    /// settings instead of an unusable capture screen.
    case setupNeeded

    /// Capture prerequisites exist. Ordinary launches open directly into
    /// capture with no dashboard or recurring welcome screen.
    case captureReady
}

enum BootstrapPolicy {
    /// Capture requires at least one active intervention type and one active
    /// drug class; service lines remain optional per I-012.
    static func state(
        hasCompletedFirstRun: Bool,
        activeInterventionTypeCount: Int,
        activeDrugClassCount: Int
    ) -> BootstrapState {
        guard hasCompletedFirstRun else {
            return .firstRun
        }
        guard activeInterventionTypeCount > 0, activeDrugClassCount > 0 else {
            return .setupNeeded
        }
        return .captureReady
    }
}
