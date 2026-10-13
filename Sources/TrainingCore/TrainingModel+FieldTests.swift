import Foundation

/// Reading a field test's result off its activity, and recording it once the athlete confirms
/// (MVP2-154).
///
/// The flow has two steps, like the max heart rate suggestion (MVP2-56), so the athlete stays in
/// control of a change that moves every zone and TRIMP score from that day on:
/// 1. ``fieldTestResult(forActivity:measurer:)`` measures the result.
/// 2. After the athlete confirms, ``applyFieldTestResult(_:asOf:)`` records it and recomputes.
///
/// An ordinary workout can only raise max heart rate (``maxHeartRateSuggestion(among:detector:)``);
/// only a test activity linked to its plan can lower it, through this flow. A host app that offers both
/// should check ``fieldTestResult(forActivity:measurer:)`` first for an activity, and not also suggest a raise
/// from the same activity.
extension TrainingModel {
    /// The result of the field test the activity `id` completed.
    ///
    /// Reads the activity, its plan and the plan's workout from the store, not the loaded window.
    ///
    /// - Parameters:
    ///   - id: The activity to measure.
    ///   - measurer: Measures the result; defaults to ``FieldTestMeasurer``'s defaults.
    /// - Returns: The result, or `nil` when the activity doesn't exist, isn't linked to a plan, or
    ///   its plan's workout isn't a field test.
    /// - Throws: ``FieldTestError`` when a test activity can't be measured, or whatever the stores
    ///   throw.
    public func fieldTestResult(
        forActivity id: UUID, measurer: FieldTestMeasurer = FieldTestMeasurer()
    ) async throws -> FieldTestResult? {
        guard let activity = try await stores.activityStore.activity(id: id),
              let workout = try await plannedWorkout(planID: activity.linkedPlanID) else { return nil }
        return try measurer.measure(
            activity, workout: workout, settings: athlete.heartRateZoneSettings(asOf: activity.start)
        )
    }

    /// Records `result` as the athlete's max heart rate or lactate threshold heart rate from the test
    /// activity's start onward, saves the profile and recomputes.
    ///
    /// Date-effective, so activities before `result.activityStart` keep their scores and the test
    /// activity and everything after it are rescored (see ``AthleteProfile/settingMaxHeartRate(to:from:source:)``
    /// and ``AthleteProfile/settingLactateThresholdHeartRate(to:from:source:)``). A max heart rate
    /// may go down. Assigning ``athlete`` invalidates the fitness-metrics cache from that date.
    ///
    /// A no-op when the activity no longer exists or is no longer linked to a field test of the kind
    /// `result` measured (it was deleted, unlinked or its plan changed since the result was read).
    ///
    /// The profile is saved before ``athlete`` is updated, so a failed save leaves the model and the
    /// store in agreement. A no-op when the profile wouldn't change. Goes through
    /// ``updateAthlete(asOf:_:)``, so it runs in the same queue as imports and other athlete updates.
    ///
    /// - Parameters:
    ///   - result: The confirmed result.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: Whatever ``AthleteStore/save(_:)`` throws; nothing is changed in that case.
    public func applyFieldTestResult(_ result: FieldTestResult, asOf today: Date = .now) async throws {
        guard let activity = try await stores.activityStore.activity(id: result.activityID),
              let workout = try await plannedWorkout(planID: activity.linkedPlanID) else { return }
        switch (result.measurement, workout.purpose) {
        case (.maxHeartRate, .maxHRTest), (.lactateThresholdHeartRate, .lthrTest): break
        default: return
        }
        try await updateAthlete(asOf: today) { athlete in
            switch result.measurement {
            case .maxHeartRate:
                athlete.settingMaxHeartRate(
                    to: result.valueBPM, from: result.activityStart, source: .fieldTest(activityID: result.activityID)
                )
            case .lactateThresholdHeartRate:
                athlete.settingLactateThresholdHeartRate(
                    to: result.valueBPM, from: result.activityStart, source: .fieldTest(activityID: result.activityID)
                )
            }
        }
    }
}
