import Foundation

extension TrainingModel {
    /// The model's base planned-load estimator, refined with the actual loads of every plan the athlete has
    /// completed (``LinkedActivityRefinedEstimator``).
    ///
    /// Reads the whole plan history from the store rather than ``plans``, which may be only the
    /// visible range, so a workout done months ago still refines next week's. If the stores can't be
    /// read, the failure is logged and the unrefined base estimator is returned: a projection without
    /// the refinement beats none.
    ///
    /// Public so a host app shows the same planned load as the load series and the calendar export do,
    /// instead of the base estimator's figure beside a refined one. It's `async` and reads every plan
    /// and each completed plan's activity on every call, with no caching, so call it once per refresh
    /// and not per card.
    ///
    /// - Returns: A ``LinkedActivityRefinedEstimator`` around the base estimator, or the base estimator
    ///   itself when no plan has been completed or the stores can't be read.
    public func refinedEstimator() async -> any PlannedLoadEstimator {
        do {
            let plans = try await stores.planStore.plans(in: Date.distantPast...Date.distantFuture)
            let completed = plans.filter { $0.completedActivityID != nil }
            guard !completed.isEmpty else { return estimator }
            let activities = try await stores.activityStore.activities(ids: completed.compactMap(\.completedActivityID))
            return LinkedActivityRefinedEstimator(
                base: estimator, plans: completed, workouts: workouts, activities: activities,
                calculators: calculators, athlete: athlete
            )
        } catch {
            Logging.load.warning("refinedEstimator() fell back to the unrefined estimator: \(error.localizedDescription, privacy: .public)")
            return estimator
        }
    }
}
