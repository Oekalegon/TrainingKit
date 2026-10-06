import Foundation
import SwiftData
import TrainingCore

/// The athlete's own preferences, the only part of the profile that syncs through CloudKit
/// (MVP2-131): name, picture, time zone, week start, main sport, the pace history and the
/// HealthKit resting-heart-rate switch. All of it is typed or chosen by the athlete.
///
/// The rest of the profile (sex, date of birth, the heart-rate settings, which come from HealthKit)
/// stays in the local-only ``AthleteProfileRecord``, since Apple's guideline 5.1.3(ii) forbids storing
/// health information in iCloud. One row per store, like ``AthleteProfileRecord``;
/// ``SwiftDataStore`` merges the two when it reads the profile.
@Model
public final class AthletePreferencesRecord {
    /// The JSON-encoded ``AthletePreferences``.
    var payload: Data = Data()

    init(payload: Data) {
        self.payload = payload
    }
}

/// What ``AthletePreferencesRecord`` stores: the fields of `AthleteProfile` that sync.
struct AthletePreferences: Codable, Equatable {
    var name: String
    var avatarImageData: Data?
    var timeZone: TimeZone
    var weekStartsOn: Weekday
    var mainSport: Sport
    var paceHistory: [PaceSettings]
    var usesHealthKitRestingHeartRate: Bool

    /// The preferences part of `profile`.
    init(of profile: AthleteProfile) {
        name = profile.name
        avatarImageData = profile.avatarImageData
        timeZone = profile.timeZone
        weekStartsOn = profile.weekStartsOn
        mainSport = profile.mainSport
        paceHistory = profile.paceHistory
        usesHealthKitRestingHeartRate = profile.usesHealthKitRestingHeartRate
    }

    /// `profile` with these preferences in place of its own.
    func apply(to profile: AthleteProfile) -> AthleteProfile {
        var merged = profile
        merged.name = name
        merged.avatarImageData = avatarImageData
        merged.timeZone = timeZone
        merged.weekStartsOn = weekStartsOn
        merged.mainSport = mainSport
        merged.paceHistory = paceHistory
        merged.usesHealthKitRestingHeartRate = usesHealthKitRestingHeartRate
        return merged
    }
}

extension AthletePreferencesRecord {
    /// Creates the record for `preferences`.
    convenience init(preferences: AthletePreferences) throws {
        self.init(payload: try PersistenceCoding.encode(preferences))
    }

    /// Decodes `payload` back into the preferences.
    func toPreferences() throws -> AthletePreferences {
        try PersistenceCoding.decode(AthletePreferences.self, from: payload)
    }

    /// Replaces `payload` with `preferences`.
    func update(from preferences: AthletePreferences) throws {
        payload = try PersistenceCoding.encode(preferences)
    }
}
