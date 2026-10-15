import Foundation

/// Changing the athlete profile safely while imports and other updates may be running (MVP2-101).
extension TrainingModel {
    /// Applies `transform` to the current ``athlete``, saves the result, assigns it and recomputes,
    /// all in the same queue as imports and other athlete updates.
    ///
    /// Every change to the athlete should go through this rather than reading ``athlete``, saving,
    /// and assigning separately. That pattern has a gap across the save's `await`: two updates
    /// started together (for example a max heart rate the athlete just accepted, and a HealthKit
    /// resting-HR refresh) each start from the same old profile, so whichever assigns last drops
    /// the other's change, and whichever saves last decides what the store keeps. Here each
    /// `transform` runs only when its turn comes, on the profile left by the update before it, so
    /// both changes survive.
    ///
    /// The profile is saved before ``athlete`` is assigned, so a failed save leaves the model and
    /// the store in agreement. Assigning ``athlete`` invalidates the fitness-metrics cache from the
    /// earliest changed date (see its `didSet`).
    ///
    /// - Parameters:
    ///   - today: Passed through to ``recompute(asOf:)``.
    ///   - transform: Returns the updated profile given the current one. Return it unchanged to do
    ///     nothing.
    /// - Returns: Whether the profile changed.
    /// - Throws: Whatever ``AthleteStore/save(_:)`` throws; nothing is changed in that case.
    @discardableResult
    public func updateAthlete(
        asOf today: Date = .now, _ transform: @escaping @Sendable (AthleteProfile) -> AthleteProfile
    ) async throws -> Bool {
        var changed = false
        try await runQueued {
            let updated = transform(self.athlete)
            guard updated != self.athlete else { return }
            try await self.stores.athleteStore.save(updated)
            self.athlete = updated
            changed = true
            await self.recompute(asOf: today)
        }
        return changed
    }
}
