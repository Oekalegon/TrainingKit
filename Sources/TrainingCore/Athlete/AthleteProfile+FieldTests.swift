import Foundation

extension AthleteProfile {
    /// This profile with max heart rate set to `bpm` from `date` onward, whether that is higher or
    /// lower than before (MVP2-154).
    ///
    /// For a measured result such as a max heart rate field test, which unlike
    /// ``raisingMaxHeartRate(to:from:source:)`` may also lower the value. Date-effective like it, so
    /// training load before `date` keeps the settings it was scored with:
    /// - The settings in effect at `date` are the baseline. If no entry starts exactly at `date`, a
    ///   copy of them is added there with the new max and `source`.
    /// - Later entries that still carry the baseline's max and source (a resting-heart-rate update
    ///   copies them) take the new max and source too, so they can't bring the old value back.
    /// - A later entry with a different max or source is a separate, later measurement and is kept.
    ///
    /// Returns the profile unchanged when it has no heart-rate settings yet, or when the max and source
    /// in effect already are `bpm` and `source`.
    ///
    /// - Parameters:
    ///   - bpm: The new max heart rate, in beats per minute.
    ///   - date: When it takes effect, usually the start of the test activity.
    ///   - source: Where the value came from.
    /// - Returns: The updated profile.
    public func settingMaxHeartRate(to bpm: Double, from date: Date, source: MaxHeartRateSource) -> AthleteProfile {
        replacingSettings(from: date) { settings, baseline in
            guard settings.maxHeartRateBPM == baseline.maxHeartRateBPM,
                  settings.maxHeartRateSource == baseline.maxHeartRateSource else { return false }
            settings.maxHeartRateBPM = bpm
            settings.maxHeartRateSource = source
            return true
        }
    }

    /// This profile with lactate threshold heart rate set to `bpm` from `date` onward (MVP2-154), by
    /// the same date-effective rules as ``settingMaxHeartRate(to:from:source:)``: the settings in
    /// effect at `date` are the baseline, and later entries that still carry its value and source take
    /// the new ones.
    ///
    /// Returns the profile unchanged when it has no heart-rate settings yet, or when the value and source
    /// in effect already are `bpm` and `source`.
    ///
    /// - Parameters:
    ///   - bpm: The new lactate threshold heart rate, in beats per minute.
    ///   - date: When it takes effect, usually the start of the test activity.
    ///   - source: Where the value came from.
    /// - Returns: The updated profile.
    public func settingLactateThresholdHeartRate(
        to bpm: Double, from date: Date, source: LactateThresholdSource
    ) -> AthleteProfile {
        replacingSettings(from: date) { settings, baseline in
            guard settings.lactateThresholdHeartRateBPM == baseline.lactateThresholdHeartRateBPM,
                  settings.lactateThresholdSource == baseline.lactateThresholdSource else { return false }
            settings.lactateThresholdHeartRateBPM = bpm
            settings.lactateThresholdSource = source
            return true
        }
    }

    /// Applies `change` to the entry at `date` (adding it, as a copy of the settings in effect, when
    /// none starts there) and then to each later entry in date order, stopping at the first one
    /// `change` declines by returning `false`. `change` gets the entry and the baseline.
    private func replacingSettings(
        from date: Date, _ change: (inout HeartRateZoneSettings, HeartRateZoneSettings) -> Bool
    ) -> AthleteProfile {
        guard let baseline = heartRateZoneSettings(asOf: date) else { return self }
        var updated = self
        if !updated.heartRateZoneHistory.contains(where: { $0.effectiveDate == date }) {
            var entry = baseline
            entry.effectiveDate = date
            updated.heartRateZoneHistory.append(entry)
        }
        let order = updated.heartRateZoneHistory.indices
            .filter { updated.heartRateZoneHistory[$0].effectiveDate >= date }
            .sorted { updated.heartRateZoneHistory[$0].effectiveDate < updated.heartRateZoneHistory[$1].effectiveDate }
        for index in order where !change(&updated.heartRateZoneHistory[index], baseline) { break }
        return updated == self ? self : updated
    }
}
