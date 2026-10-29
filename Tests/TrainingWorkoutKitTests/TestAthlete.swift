import Foundation
import TrainingCore

/// An athlete with Karvonen zones (rest 50, max 190): zone 3 is 148...162 bpm.
let testAthlete = AthleteProfile(
    name: "Test Athlete",
    sex: .male,
    paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
    timeZone: TimeZone(identifier: "UTC")!,
    heartRateZoneHistory: [
        HeartRateZoneSettings(effectiveDate: .distantPast, restingHeartRateBPM: 50, maxHeartRateBPM: 190, zoneMethod: .karvonen),
    ]
)
