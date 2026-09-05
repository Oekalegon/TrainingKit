/// A source of completed activities external to `TrainingCore`, e.g. HealthKit or a FIT file.
///
/// Adapter targets implement this against their own platform APIs; `TrainingCore` only sees the
/// resulting `[Activity]`/``ImportAnchor``, never the platform types that produced them.
public protocol ActivityImporting: Sendable {
    /// Imports activities added, updated, or deleted since `anchor`.
    ///
    /// - Parameter anchor: The cursor from the previous call's ``ImportResult/anchor``, or `nil`
    ///   for a full import.
    /// - Returns: The activities to upsert, the sources to delete, and the anchor to persist for
    ///   next time.
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult
}
