import Foundation
import TrainingCore

extension AthleteProfile {
    /// A minimal athlete with a single heart-rate zone settings entry effective since the
    /// beginning of time, for tests that don't care about zone history.
    static func fixture() -> AthleteProfile {
        AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: [
                HeartRateZoneSettings(
                    effectiveDate: .distantPast,
                    restingHeartRateBPM: 50,
                    maxHeartRateBPM: 190,
                    lactateThresholdHeartRateBPM: nil,
                    zoneMethod: .karvonen
                )
            ]
        )
    }
}
