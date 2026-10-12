import Foundation


extension Activity {
    /// This activity with the sport and venue of the planned workout it completes, unless the athlete
    /// chose its own (``isSportEdited``).
    ///
    /// The workout's venue, else the athlete's usual one for its sport
    /// (``AthleteProfile/defaultVenue(for:)``), else the venue the activity was recorded with. The
    /// result isn't marked ``isSportEdited``: it follows the plan, so a later link to another plan
    /// changes it again.
    ///
    /// - Parameters:
    ///   - workout: The workout of the plan the activity is linked to; `nil` changes nothing.
    ///   - athlete: Supplies the usual venue.
    public func adoptingSportAndVenue(of workout: StructuredWorkout?, athlete: AthleteProfile) -> Activity {
        guard let workout, !isSportEdited else { return self }
        var adopted = self
        adopted.sport = workout.sport
        adopted.venue = workout.venue ?? athlete.defaultVenue(for: workout.sport) ?? venue
        return adopted
    }
}

extension TrainingModel {
    /// The workout of the plan `planID`, read from the store.
    func plannedWorkout(planID: UUID?) async throws -> StructuredWorkout? {
        guard let planID, let plan = try await stores.planStore.plan(id: planID) else { return nil }
        return try await stores.workoutStore.workout(id: plan.workoutID)
    }
}
