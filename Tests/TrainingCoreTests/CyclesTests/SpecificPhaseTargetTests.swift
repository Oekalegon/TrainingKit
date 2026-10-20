import Foundation
import Testing
@testable import TrainingCore

@Suite("SpecificPhaseTarget")
struct SpecificPhaseTargetTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("each kind round-trips through Codable, alone and on a race")
    func roundTrip() throws {
        let targets: [SpecificPhaseTarget] = [
            .pace(secondsPerKilometer: 240), .heartRate(beatsPerMinute: 165...172),
            .perceivedEffort(8), .predictedFromFitness,
        ]
        for target in targets {
            try target.validate()
            #expect(try JSONDecoder().decode(SpecificPhaseTarget.self, from: JSONEncoder().encode(target)) == target)
            let race = Race(name: "10K", date: date, priority: .primary, distanceMeters: 10_000, specificPhaseTarget: target)
            #expect(try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(race)) == race)
        }
    }

    @Test("a single heart rate is a range with equal bounds")
    func singleHeartRate() throws {
        try SpecificPhaseTarget.heartRate(beatsPerMinute: 170...170).validate()
    }

    @Test("nonsense values are rejected by validate")
    func invalidValues() {
        #expect(throws: SpecificPhaseTargetError.invalidPace) { try SpecificPhaseTarget.pace(secondsPerKilometer: 0).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidPace) { try SpecificPhaseTarget.pace(secondsPerKilometer: -5).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidPace) { try SpecificPhaseTarget.pace(secondsPerKilometer: .nan).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidPace) { try SpecificPhaseTarget.pace(secondsPerKilometer: .infinity).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidHeartRate) { try SpecificPhaseTarget.heartRate(beatsPerMinute: 0...150).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidHeartRate) { try SpecificPhaseTarget.heartRate(beatsPerMinute: 150...(.infinity)).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidPerceivedEffort) { try SpecificPhaseTarget.perceivedEffort(0).validate() }
        #expect(throws: SpecificPhaseTargetError.invalidPerceivedEffort) { try SpecificPhaseTarget.perceivedEffort(11).validate() }
    }

    @Test("decoding validates")
    func decodingValidates() {
        #expect(throws: SpecificPhaseTargetError.invalidPace) {
            try decode(SpecificPhaseTarget.self, #"{"pace":{"secondsPerKilometer":-1}}"#)
        }
        #expect(throws: SpecificPhaseTargetError.invalidPerceivedEffort) {
            try decode(SpecificPhaseTarget.self, #"{"perceivedEffort":{"_0":11}}"#)
        }
        #expect(throws: SpecificPhaseTargetError.invalidHeartRate) {
            try decode(SpecificPhaseTarget.self, #"{"heartRate":{"beatsPerMinute":[0,150]}}"#)
        }
        #expect(throws: DecodingError.self) {
            try decode(SpecificPhaseTarget.self, #"{"heartRate":{"beatsPerMinute":[170,150]}}"#)
        }
    }

    @Test("a race stored before the target existed decodes to nil")
    func legacyRace() throws {
        let id = UUID()
        let race = try decode(Race.self, #"{"id":"\#(id.uuidString)","name":"Old","date":1000,"priority":{"primary":{}},"distanceMeters":10000}"#)
        #expect(race.specificPhaseTarget == nil && race.id == id)
    }

    @Test("a race with an unknown or invalid target keeps the race and drops the target")
    func tolerantRace() throws {
        let id = UUID()
        for target in [#"{"telepathy":{}}"#, #"{"pace":{"secondsPerKilometer":0}}"#] {
            let race = try decode(
                Race.self, #"{"id":"\#(id.uuidString)","name":"New","date":1000,"priority":{"primary":{}},"distanceMeters":10000,"specificPhaseTarget":\#(target)}"#
            )
            #expect(race.name == "New" && race.specificPhaseTarget == nil)
        }
    }
}
