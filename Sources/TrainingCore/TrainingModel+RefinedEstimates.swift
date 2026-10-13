import Foundation

extension TrainingModel {
    /// The model's base planned-load estimator, refined with the actual loads of every plan the athlete has
    /// completed (``LinkedActivityRefinedEstimator``).
    ///
    /// Reads the whole plan history from the store rather than ``plans``, which may be only the
    /// visible range, so a workout done months ago still refines next week's. If the stores can't be
    /// read, the failure is logged and the unrefined base estimator is returned: a projection without
    /// the refinement beats none. A caller that needs to tell "nothing to refine" from "couldn't read"
    /// uses ``loadRefinedEstimator()``.
    ///
    /// Public so a host app shows the same planned load as the load series and the calendar export do,
    /// instead of the base estimator's figure beside a refined one. Building it reads every plan and each
    /// completed plan's activity and scores them, so the result is kept (see ``loadRefinedEstimator()``):
    /// calling this after an import, link or any other change that went through the model costs
    /// nothing, as ``recompute(asOf:)`` has just built it, and after an import that found nothing new
    /// it is the one already kept.
    ///
    /// - Returns: A ``LinkedActivityRefinedEstimator`` around the base estimator, or the base estimator
    ///   itself when no plan has been completed or the stores can't be read.
    public func refinedEstimator() async -> any PlannedLoadEstimator {
        do {
            return try await loadRefinedEstimator()
        } catch {
            Logging.load.warning("refinedEstimator() fell back to the unrefined estimator: \(error.localizedDescription, privacy: .public)")
            return estimator
        }
    }

    /// ``refinedEstimator()``, throwing when the stores can't be read instead of falling back to the base
    /// estimator, so a host app can keep the refinement it already shows through a transient failure
    /// and retry, rather than mistake the failure for "no plan has been completed".
    ///
    /// The estimator is built once and kept until the next ``recompute(asOf:)`` that follows a change,
    /// which every mutation of the activities, plans, workouts or athlete goes through: an import that
    /// brought or removed something, a link, join, delete, edit or profile change. An import that found
    /// nothing new keeps it (MVP2-161). Concurrent callers share one build. A failed build isn't kept,
    /// so the next call tries again. Changes made to the stores without going through this model (an
    /// iCloud sync, say) aren't seen until then, as with ``metrics``.
    ///
    /// - Returns: A ``LinkedActivityRefinedEstimator`` around the base estimator, or the base estimator
    ///   itself when no plan has been completed.
    /// - Throws: Whatever the plan or activity store throws.
    public func loadRefinedEstimator() async throws -> any PlannedLoadEstimator {
        if let build = refinedEstimatorBuild, build.epoch == refinedEstimatorEpoch {
            return try await build.task.value
        }
        let epoch = refinedEstimatorEpoch
        let task = Task { try await self.buildRefinedEstimator() }
        refinedEstimatorBuild = (epoch, task)
        do {
            return try await task.value
        } catch {
            // Don't keep a failure: the next call reads the stores again.
            if refinedEstimatorBuild?.epoch == epoch { refinedEstimatorBuild = nil }
            throw error
        }
    }

    /// Forgets the kept estimator, because something it was built from changed. A build already
    /// running finishes for the callers waiting on it, but isn't kept.
    func invalidateRefinedEstimator() {
        refinedEstimatorEpoch += 1
        refinedEstimatorBuild = nil
    }

    private func buildRefinedEstimator() async throws -> any PlannedLoadEstimator {
        refinedEstimatorBuildCount += 1
        let plans = try await stores.planStore.plans(in: Date.distantPast...Date.distantFuture)
        let completed = plans.filter { $0.completedActivityID != nil }
        guard !completed.isEmpty else { return estimator }
        let activities = try await stores.activityStore.activities(ids: completed.compactMap(\.completedActivityID))
        return LinkedActivityRefinedEstimator(
            base: estimator, plans: completed, workouts: workouts, activities: activities,
            calculators: calculators, athlete: athlete
        )
    }
}
