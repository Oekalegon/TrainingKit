#if canImport(HealthKit)
import HealthKit
import Foundation
import Testing
@testable import TrainingHealthKit

@Suite("HealthKitAthleteReader")
struct HealthKitAthleteReaderTests {
    @Test("snapshot(asOf:) never throws or crashes when HealthKit itself is unavailable, and every field independently reports nil")
    func snapshotDegradesGracefullyWhenHealthKitUnavailable() async {
        // On a host/simulator with no Health data at all, every HealthKit call below throws the
        // same "Health data is unavailable" error -- confirmed by directly probing HKHealthStore
        // in this environment. Before the fix, any one of these throwing (e.g. the
        // dateOfBirthComponents() / biologicalSex() characteristic reads, which throw on missing
        // authorization unlike sample queries) took the whole snapshot down via a single
        // `try await` on the combined result, discarding whatever *did* succeed. snapshot(asOf:)
        // no longer throws at all, so this test alone proves that regression can't recur: if any
        // field's failure still propagated, this call wouldn't compile without `try`, let alone
        // return.
        let reader = HealthKitAthleteReader(healthStore: HKHealthStore())

        let snapshot = await reader.snapshot(asOf: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.restingHeartRateBPM == nil)
        #expect(snapshot.biologicalSex == nil)
        #expect(snapshot.estimatedMaxHeartRateBPM == nil)
    }
}
#endif
