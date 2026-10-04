import Foundation

/// Keeping ``TrainingModel/paceHistory`` current (MVP2-35, MVP2-111).
extension TrainingModel {
    /// Rebuilds ``paceHistory`` from every stored activity in `range`, rather than only the loaded
    /// ``activities``, so a planned workout can be forecast from months of earlier runs while the
    /// app shows a few weeks. Linked plans in `range` are read too, so each linked activity's steps
    /// can be laid over its recording.
    ///
    /// Reads the store and leaves ``activities``, ``plans`` and ``metrics`` untouched. On a failed
    /// read ``paceHistory`` keeps its previous value. The history is built off the main actor.
    ///
    /// - Parameters:
    ///   - range: The activity start dates to learn from, inclusive on both ends — for example the
    ///     last 180 days, long enough to have run most kinds of workout and short enough to reflect
    ///     current fitness.
    ///   - gapThresholdSeconds: Samples further apart than this are a pause; pass the
    ///     ``StatisticsCalculator/gapThresholdSeconds`` the statistics are computed with.
    /// - Throws: Whatever the activity or plan store throws.
    public func refreshPaceHistory(
        in range: ClosedRange<Date>,
        gapThresholdSeconds: TimeInterval = StatisticsCalculator().gapThresholdSeconds
    ) async throws {
        let activities = try await stores.activityStore.activities(in: range)
        let plans = try await stores.planStore.plans(in: range)
        let workouts = self.workouts
        let athlete = self.athlete
        paceHistory = await Task.detached(priority: .utility) {
            PaceHistory(
                activities: activities, plans: plans, workouts: workouts,
                athlete: athlete, gapThresholdSeconds: gapThresholdSeconds
            )
        }.value
    }
}
