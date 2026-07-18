import Foundation

/// Pure ranking inputs. The capture screen fetches a small active-taxonomy set
/// and a bounded recent-intervention window, converts them to these values,
/// and ranks off the main model graph so the policy stays testable and
/// SwiftUI-free (architecture: capture never owns an unbounded query).
struct RankableType: Equatable, Sendable {
    let id: UUID
    let sortOrder: Int
    let label: String
}

/// One recent use of a type, newest-relevant by timestamp. Only the type's
/// identity and when it was used matter to ranking.
struct TypeUsage: Equatable, Sendable {
    let typeID: UUID
    let usedAt: Date
}

/// Frecency = frequency within a bounded window, then recency, then the
/// configured stable order. The result is deterministic for identical inputs
/// so tests and the UI agree exactly.
enum FrecencyRanking {
    /// Ranks `types` by, in order:
    /// 1. descending use count within `recentUsage`;
    /// 2. descending most-recent use (an unused type sorts after any used one);
    /// 3. ascending configured `sortOrder`; then
    /// 4. ascending case-insensitive label as the final stable tie-breaker.
    ///
    /// Usage entries whose `typeID` is not among `types` are ignored, so a
    /// window spanning since-deactivated types cannot distort the order.
    static func rank(
        types: [RankableType],
        recentUsage: [TypeUsage]
    ) -> [RankableType] {
        let liveIDs = Set(types.map(\.id))
        var useCount: [UUID: Int] = [:]
        var lastUsed: [UUID: Date] = [:]
        for usage in recentUsage where liveIDs.contains(usage.typeID) {
            useCount[usage.typeID, default: 0] += 1
            if let existing = lastUsed[usage.typeID] {
                lastUsed[usage.typeID] = max(existing, usage.usedAt)
            } else {
                lastUsed[usage.typeID] = usage.usedAt
            }
        }

        return types.sorted { left, right in
            let leftCount = useCount[left.id, default: 0]
            let rightCount = useCount[right.id, default: 0]
            if leftCount != rightCount {
                return leftCount > rightCount
            }
            let leftLast = lastUsed[left.id]
            let rightLast = lastUsed[right.id]
            if leftLast != rightLast {
                return isMoreRecent(leftLast, than: rightLast)
            }
            if left.sortOrder != right.sortOrder {
                return left.sortOrder < right.sortOrder
            }
            return left.label.lowercased() < right.label.lowercased()
        }
    }

    /// A present timestamp outranks an absent one; two present timestamps
    /// compare normally. Keeping this explicit avoids sorting `nil` as if it
    /// were the distant past through optional coercion.
    private static func isMoreRecent(_ candidate: Date?, than other: Date?) -> Bool {
        switch (candidate, other) {
        case let (lhs?, rhs?):
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }
}
