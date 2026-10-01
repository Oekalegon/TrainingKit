import Foundation

/// Raising the athlete's max heart rate when a workout shows it is higher than the value on
/// record (MVP2-56).
///
/// The flow has two steps, so the athlete stays in control of a change that moves every zone and
/// every TRIMP score from that day on:
/// 1. ``maxHeartRateSuggestion(among:detector:)`` or ``scanForMaxHeartRateSuggestion(in:excluding:detector:)`` finds a workout
///    whose held peak beats the current max.
/// 2. After the athlete confirms, ``applyMaxHeartRate(_:asOf:)`` records it and recomputes.
extension TrainingModel {
    /// The workout among `activities` with the highest held heart rate above the athlete's current
    /// max, if any.
    ///
    /// Compares against ``AthleteProfile/currentHeartRateZoneSettings`` rather than the settings in
    /// effect on each activity's date: max heart rate only rises through this flow, so an old
    /// activity that beat an old, lower max but not today's is no longer news. Peaks are found by
    /// `detector` and rounded to a whole bpm before comparing, so a peak must exceed the current max
    /// by at least 1 bpm. On equal peaks the most recent activity wins.
    ///
    /// - Parameters:
    ///   - activities: The activities to consider, e.g. ``activities`` after an import.
    ///   - detector: Finds each activity's held peak; defaults to ``PeakHeartRateDetector``'s
    ///     defaults.
    /// - Returns: The best suggestion, or `nil` when no activity beats the current max or no heart
    ///   rate settings are recorded yet.
    public func maxHeartRateSuggestion(
        among activities: [Activity], detector: PeakHeartRateDetector = PeakHeartRateDetector()
    ) -> MaxHeartRateSuggestion? {
        guard let currentMax = athlete.currentHeartRateZoneSettings?.maxHeartRateBPM else { return nil }
        var best: MaxHeartRateSuggestion?
        for activity in activities {
            guard let peak = detector.sustainedPeak(in: activity.heartRate) else { continue }
            let peakBPM = peak.bpm.rounded()
            guard peakBPM > currentMax.rounded() else { continue }
            let isBetter = best.map {
                peakBPM > $0.peakBPM || (peakBPM == $0.peakBPM && activity.start > $0.activityStart)
            } ?? true
            if isBetter {
                best = MaxHeartRateSuggestion(
                    activityID: activity.id, sport: activity.sport, activityStart: activity.start,
                    peakBPM: peakBPM, currentMaxBPM: currentMax
                )
            }
        }
        return best
    }

    /// Like ``maxHeartRateSuggestion(among:detector:)``, but over every stored activity in `range` rather
    /// than the loaded ``activities``. For a one-time look back over the athlete's history (for
    /// example the last 12 months; max heart rate falls with age, so much older peaks shouldn't
    /// count).
    ///
    /// Reads the store directly and leaves ``activities`` and ``metrics`` untouched.
    ///
    /// - Parameters:
    ///   - range: The activity start dates to scan, inclusive on both ends.
    ///   - excludedIDs: Activities to skip, e.g. ones the athlete already declined, so the next-best
    ///     activity can still be suggested.
    ///   - detector: Finds each activity's held peak.
    /// - Returns: The best suggestion in `range`, or `nil`.
    /// - Throws: Whatever ``ActivityStore/activities(in:)`` throws.
    public func scanForMaxHeartRateSuggestion(
        in range: ClosedRange<Date>, excluding excludedIDs: Set<UUID> = [],
        detector: PeakHeartRateDetector = PeakHeartRateDetector()
    ) async throws -> MaxHeartRateSuggestion? {
        let stored = try await stores.activityStore.activities(in: range).filter { !excludedIDs.contains($0.id) }
        return maxHeartRateSuggestion(among: stored, detector: detector)
    }

    /// Records `suggestion`'s peak as the athlete's max heart rate from that activity onward, saves
    /// the profile and recomputes.
    ///
    /// Uses ``AthleteProfile/raisingMaxHeartRate(to:from:source:)``, so the change is raise-only
    /// and date-effective: activities before `suggestion.activityStart` keep their scores, and the
    /// activity itself and everything after it are rescored. Assigning ``athlete`` invalidates the
    /// fitness-metrics cache from that date.
    ///
    /// The profile is saved before ``athlete`` is updated, so a failed save leaves the model and
    /// the store in agreement. A no-op when the profile wouldn't change (for example the max was
    /// already raised past this peak).
    ///
    /// - Parameters:
    ///   - suggestion: The confirmed suggestion.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: Whatever ``AthleteStore/save(_:)`` throws; nothing is changed in that case.
    public func applyMaxHeartRate(_ suggestion: MaxHeartRateSuggestion, asOf today: Date = .now) async throws {
        let updated = athlete.raisingMaxHeartRate(
            to: suggestion.peakBPM, from: suggestion.activityStart,
            source: .workout(activityID: suggestion.activityID)
        )
        guard updated != athlete else { return }
        try await stores.athleteStore.save(updated)
        athlete = updated
        await recompute(asOf: today)
    }
}
