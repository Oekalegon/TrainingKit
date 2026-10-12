import Foundation

/// Changes the athlete makes to a performed activity.
extension TrainingModel {
    /// Sets the sport and venue of the activity `id`, e.g. when the Watch recorded a treadmill run as
    /// outdoors, and marks it ``Activity/isSportEdited`` so a later re-import or join rebuild keeps
    /// the choice.
    ///
    /// Neither sport nor venue feeds the recorded training load, so the fitness series isn't recomputed
    /// for the activity itself. A joined activity the activity is a piece of is rebuilt from its pieces
    /// (see ``refreshJoins(containing:)``), which does recompute. Reloads ``activities`` from the store.
    ///
    /// Sport and venue do feed the forecast of future plans, through ``paceHistory``'s observations:
    /// call ``refreshPaceHistory(in:gapThresholdSeconds:)`` afterwards so the forecasts follow. The activity keeps its plan link, even if the new sport
    /// wouldn't have matched that plan. Looks the activity up in the store, not in the loaded
    /// window, and does nothing if it doesn't exist. Serialized with imports through the same queue.
    ///
    /// - Parameters:
    ///   - sport: The sport to set.
    ///   - venue: The venue to set, or `nil` for none.
    ///   - id: The activity to change.
    ///   - today: Used for the range reloaded when nothing has been loaded yet.
    public func setSport(_ sport: Sport, venue: Venue?, forActivityID id: UUID, asOf today: Date = .now) async throws {
        try await runQueued {
            guard var activity = try await self.stores.activityStore.activity(id: id) else { return }
            guard activity.sport != sport || activity.venue != venue || !activity.isSportEdited else { return }
            activity.sport = sport
            activity.venue = venue
            activity.isSportEdited = true
            try await self.stores.activityStore.upsert([activity])
            let range = self.loadedRange ?? (today...today)
            let days = try await self.stores.activityStore.joinedActivity(containing: id) == nil
                ? [] : try await self.refreshJoins(containing: [id])
            if let earliest = days.min() {
                try await self.reloadAfterJoinChange(from: earliest, asOf: today)
            } else {
                self.activities = try await self.stores.activityStore.activities(in: range)
            }
        }
    }
}
