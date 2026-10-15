import Foundation

extension AthleteProfile {
    /// This profile with max heart rate raised to `bpm` from `date` onward.
    ///
    /// Raise-only and date-effective, so past training load keeps the settings it was scored
    /// with:
    /// - Entries effective before `date` are left alone.
    /// - Entries effective on or after `date` whose max is below `bpm` are raised to it and take
    ///   `source`, so a later entry (for example a resting-HR update) can't bring the old max back.
    /// - If no entry starts exactly at `date`, a copy of the settings in effect at `date` is added
    ///   there with the raised max.
    ///
    /// Returns the profile unchanged when it has no heart-rate settings yet (there is no resting
    /// heart rate or zone method to copy) or when no entry from `date` onward is below `bpm`.
    ///
    /// - Parameters:
    ///   - bpm: The new max heart rate, in beats per minute.
    ///   - date: When the new max takes effect, usually the start of the activity that reached it.
    ///   - source: Where the new value came from.
    /// - Returns: The updated profile.
    public func raisingMaxHeartRate(to bpm: Double, from date: Date, source: MaxHeartRateSource) -> AthleteProfile {
        guard let inEffect = heartRateZoneSettings(asOf: date) else { return self }
        let needsNewEntry = inEffect.maxHeartRateBPM < bpm
            && !heartRateZoneHistory.contains { $0.effectiveDate == date }
        var updated = self
        var changed = false
        for index in updated.heartRateZoneHistory.indices
        where updated.heartRateZoneHistory[index].effectiveDate >= date
            && updated.heartRateZoneHistory[index].maxHeartRateBPM < bpm {
            updated.heartRateZoneHistory[index].maxHeartRateBPM = bpm
            updated.heartRateZoneHistory[index].maxHeartRateSource = source
            changed = true
        }
        if needsNewEntry {
            var entry = inEffect
            entry.effectiveDate = date
            entry.maxHeartRateBPM = bpm
            entry.maxHeartRateSource = source
            updated.heartRateZoneHistory.append(entry)
            changed = true
        }
        return changed ? updated : self
    }
}
