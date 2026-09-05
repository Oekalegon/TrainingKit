import Foundation
@testable import TrainingCore

extension AthleteProfile {
    /// A minimal athlete with a single heart-rate zone settings entry effective since the
    /// beginning of time, for tests that don't care about zone history.
    static func fixture(
        restingHeartRateBPM: Double = 50,
        maxHeartRateBPM: Double = 190,
        lactateThresholdHeartRateBPM: Double? = nil,
        zoneMethod: HeartRateZoneMethod = .karvonen,
        sex: BiologicalSex = .male,
        thresholdPaceSecondsPerKilometer: Double = 240,
        timeZoneIdentifier: String = "UTC"
    ) -> AthleteProfile {
        AthleteProfile(
            sex: sex,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: thresholdPaceSecondsPerKilometer),
            timeZone: TimeZone(identifier: timeZoneIdentifier)!,
            heartRateZoneHistory: [
                HeartRateZoneSettings(
                    effectiveDate: .distantPast,
                    restingHeartRateBPM: restingHeartRateBPM,
                    maxHeartRateBPM: maxHeartRateBPM,
                    lactateThresholdHeartRateBPM: lactateThresholdHeartRateBPM,
                    zoneMethod: zoneMethod
                )
            ]
        )
    }
}
