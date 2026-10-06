import Foundation

/// Changes the athlete makes by hand (MVP2-132), as pure functions of the profile. A host app applies
/// them through `TrainingModel.updateAthlete(asOf:_:)`, which saves, recomputes and invalidates the
/// fitness-metrics cache from the earliest changed date.
///
/// Each takes effect from a calendar day in the athlete's ``AthleteProfile/timeZone``, counted from
/// the start of that day, so an activity that morning is scored with it. Recording on a day that
/// already has an entry replaces that entry rather than adding a second one for the same day.
extension AthleteProfile {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Records `settings` from its `effectiveDate`'s day, replacing the entry for that day if there is
    /// one.
    ///
    /// - Parameter settings: The resting and maximum heart rate, lactate threshold and zone method to
    ///   apply; its `effectiveDate` is moved to the start of its day.
    /// - Returns: The updated profile.
    public func recordingHeartRateSettings(_ settings: HeartRateZoneSettings) -> AthleteProfile {
        var updated = self
        var entry = settings
        entry.effectiveDate = calendar.startOfDay(for: settings.effectiveDate)
        updated.heartRateZoneHistory.removeAll { calendar.isDate($0.effectiveDate, inSameDayAs: entry.effectiveDate) }
        updated.heartRateZoneHistory.append(entry)
        return updated
    }

    /// Removes the heart-rate settings entry for `date`'s day, unless it's the only one: scoring
    /// needs settings for every date.
    ///
    /// - Parameter date: Any instant on the entry's day.
    /// - Returns: The updated profile, or this one when there's no entry that day or it's the last.
    public func removingHeartRateSettings(on date: Date) -> AthleteProfile {
        guard heartRateZoneHistory.count > 1,
              heartRateZoneHistory.contains(where: { calendar.isDate($0.effectiveDate, inSameDayAs: date) })
        else { return self }
        var updated = self
        updated.heartRateZoneHistory.removeAll { calendar.isDate($0.effectiveDate, inSameDayAs: date) }
        return updated
    }

    /// Records `paceModel` from `date`'s day, replacing the entry for that day if there is one.
    ///
    /// - Parameters:
    ///   - paceModel: The pace model to apply.
    ///   - date: Any instant on the day it takes effect.
    /// - Returns: The updated profile.
    public func recordingPaceModel(_ paceModel: PaceModel, from date: Date) -> AthleteProfile {
        var updated = self
        let day = calendar.startOfDay(for: date)
        updated.paceHistory.removeAll { calendar.isDate($0.effectiveDate, inSameDayAs: day) }
        updated.paceHistory.append(PaceSettings(effectiveDate: day, paceModel: paceModel))
        return updated
    }

    /// Removes the pace entry for `date`'s day, unless it's the only one.
    ///
    /// - Parameter date: Any instant on the entry's day.
    /// - Returns: The updated profile, or this one when there's no entry that day or it's the last.
    public func removingPaceSettings(on date: Date) -> AthleteProfile {
        guard paceHistory.count > 1, paceHistory.contains(where: { calendar.isDate($0.effectiveDate, inSameDayAs: date) })
        else { return self }
        var updated = self
        updated.paceHistory.removeAll { calendar.isDate($0.effectiveDate, inSameDayAs: date) }
        return updated
    }
}
