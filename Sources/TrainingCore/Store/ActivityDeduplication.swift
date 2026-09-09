import Foundation

/// Shared tie-break for ``ActivityStore/deduplicateActivities()`` implementations, so
/// `InMemoryStore` and `SwiftDataStore` agree on which of a group of duplicate `Activity` rows
/// (same non-manual `source`) survives.
public enum ActivityDeduplication {
    /// Orders `group` (all sharing one `source`) so the activity to keep is `first`.
    ///
    /// Prefers more heart-rate samples: two rows for the same underlying workout can differ in
    /// completeness rather than being truly interchangeable — e.g. one imported before a fix to
    /// how HR series samples are unpacked on import, one after. Keeping the row with fewer/no
    /// samples would silently regress that fix for exactly the activities a cleanup like this is
    /// meant to help. Falls back to the smallest `id` when sample counts tie, purely for a stable,
    /// deterministic order — duplicates that are otherwise identical have no principled "better"
    /// choice to make.
    public static func ordered(_ group: [Activity]) -> [Activity] {
        group.sorted { lhs, rhs in
            if lhs.heartRate.count != rhs.heartRate.count {
                return lhs.heartRate.count > rhs.heartRate.count
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
