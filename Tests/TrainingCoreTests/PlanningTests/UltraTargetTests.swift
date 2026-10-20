import Foundation
import Testing
@testable import TrainingCore

@Suite("Ultra target (MVP5-138)")
struct UltraTargetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }
    private func race(_ meters: Double) -> Race {
        Race(name: "Target", date: day(100), priority: .primary, distanceMeters: meters)
    }

    private let marathon = 42_195.0
    private let ultra = 100_000.0

    private func longOffsets(_ result: DayAssignmentResult) -> [Int] {
        result.assignments.filter { $0.runType == .long }.map { calendar.dateComponents([.day], from: monday, to: $0.day).day! }
    }

    private func assign(days: Int, long: Int, paradigm: TrainingParadigm, target: Race?) -> DayAssignmentResult {
        let avail = RunAvailability(slots: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, [DaySlot.morning]) }))
        return DayAssigner(paradigm: paradigm).assign(
            micro: day(0)...day(days - 1), availability: avail, hardCount: 0, longCount: long, targetRace: target, calendar: calendar
        )
    }

    // MARK: Race

    @Test("a race is an ultra only when longer than a marathon")
    func isUltra() {
        #expect(!race(42_195).isUltra)
        #expect(race(42_196).isUltra)
        #expect(race(100_000).isUltra)
        #expect(!race(10_000).isUltra)
    }

    @Test("a race needs a finite distance above zero")
    func validation() throws {
        for bad in [0.0, -1, .infinity, .nan] {
            #expect(throws: RaceError.invalidDistance) { try race(bad).validate() }
        }
        try race(1).validate()
    }

    @Test("a race round-trips; one stored without a distance, or with a bad one, does not decode")
    func codable() throws {
        let value = race(ultra)
        #expect(try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(value)) == value)

        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["distanceMeters"] = 0
        #expect(throws: RaceError.invalidDistance) {
            try JSONDecoder().decode(Race.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object.removeValue(forKey: "distanceMeters")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Race.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("the in-memory store refuses a race with an invalid distance")
    func storeRefuses() async {
        await #expect(throws: RaceError.invalidDistance) { try await InMemoryStore().upsert([race(0)]) }
    }

    // MARK: Paradigm

    @Test("resolving for an ultra turns long-run spacing off and keeps the ultra settings")
    func resolvedUltra() {
        var base = TrainingParadigm.polarized8020
        base.maxLongRunMeters = 40_000
        base.maxBackToBackLongRunPairsPerMicro = [7: 1]
        let resolved = base.resolved(for: race(ultra))
        #expect(!resolved.spacesLongRunsAsHard)
        #expect(resolved.maxLongRunMeters == 40_000 && resolved.maxBackToBackLongRunPairsPerMicro == [7: 1])
        #expect(resolved.minDaysBetweenHardSessions == base.minDaysBetweenHardSessions)
        #expect(resolved.phaseMixes == base.phaseMixes && resolved.maxHardSessionsPerMicro == base.maxHardSessionsPerMicro)
    }

    @Test("with a marathon or no target race the paradigm is unchanged except the ultra settings are dropped")
    func resolvedOther() {
        var base = TrainingParadigm.polarized8020
        base.maxLongRunMeters = 40_000
        base.maxBackToBackLongRunPairsPerMicro = [7: 1]
        for target in [race(marathon), nil] {
            let resolved = base.resolved(for: target)
            #expect(resolved.spacesLongRunsAsHard)
            #expect(resolved.maxLongRunMeters == nil && resolved.maxBackToBackLongRunPairsPerMicro.isEmpty)
        }
        var expected = TrainingParadigm.polarized8020
        expected.maxLongRunMeters = nil
        expected.maxBackToBackLongRunPairsPerMicro = [:]
        #expect(TrainingParadigm.polarized8020.resolved(for: nil) == expected)
    }

    @Test("both built-ins allow 35 km and 1, 1 and 2 back-to-back pairs per 7-, 10- and 14-day micro")
    func builtInNumbers() {
        for paradigm in TrainingParadigm.builtIn {
            #expect(paradigm.maxLongRunMeters == 35_000)
            #expect(paradigm.maxBackToBackLongRunPairsPerMicro == [7: 1, 10: 1, 14: 2])
            #expect(paradigm.resolved(for: race(ultra)).maxLongRunMeters == 35_000)
            #expect(paradigm.resolved(for: nil).maxLongRunMeters == nil)
        }
    }

    @Test("the ultra settings round-trip, and a payload without them decodes to none")
    func codableSettings() throws {
        var paradigm = TrainingParadigm(name: "X")
        paradigm.maxLongRunMeters = 40_000
        paradigm.maxBackToBackLongRunPairsPerMicro = [7: 1, 14: 2]
        #expect(try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(paradigm)) == paradigm)
        let legacy = try JSONDecoder().decode(TrainingParadigm.self, from: Data(#"{"name":"Old"}"#.utf8))
        #expect(legacy.maxLongRunMeters == 35_000 && legacy.maxBackToBackLongRunPairsPerMicro.isEmpty)
    }

    // MARK: Spacing rule

    @Test("the spacing rule flags back-to-back long runs, unless the target is an ultra")
    func evaluatorSpacing() {
        let sessions = [
            PlanSession(day: day(2), seconds: 9000, intensity: .low, speed: .slow, isLongRun: true),
            PlanSession(day: day(3), seconds: 9000, intensity: .low, speed: .slow, isLongRun: true),
        ]
        func findings(_ target: Race?) -> [PlanFinding] {
            PlanEvaluator().evaluate([], races: [], sessions: sessions, paradigm: .polarized8020, targetRace: target)
                .findings.filter { $0.rule == .hardSessionSpacing }
        }
        #expect(!findings(nil).isEmpty)
        #expect(!findings(race(marathon)).isEmpty)
        #expect(findings(race(ultra)).isEmpty)
    }

    // MARK: Day assigner

    @Test("for 7-, 10- and 14-day micros long runs are spaced without an ultra and may touch with one")
    func assignerSpacing() {
        for days in [7, 10, 14] {
            let spaced = assign(days: days, long: 2, paradigm: .polarized8020, target: race(marathon))
            #expect(longOffsets(spaced) == [0, 2], "\(days)-day micro")
            let ultraResult = assign(days: days, long: 2, paradigm: .polarized8020, target: race(ultra))
            #expect(longOffsets(ultraResult) == [0, 1], "\(days)-day micro")
        }
    }

    @Test("the pair cap limits back-to-back long runs per micro length; the rest are dropped")
    func pairCap() {
        var paradigm = TrainingParadigm.polarized8020
        paradigm.maxBackToBackLongRunPairsPerMicro = [7: 0, 10: 1, 14: 2]

        let seven = assign(days: 7, long: 2, paradigm: paradigm, target: race(ultra))
        #expect(longOffsets(seven).count == 2)
        #expect(zip(longOffsets(seven), longOffsets(seven).dropFirst()).allSatisfy { $1 - $0 > 1 })

        let ten = assign(days: 10, long: 3, paradigm: paradigm, target: race(ultra))
        let tenOffsets = longOffsets(ten)
        #expect(tenOffsets.count == 3 && ten.dropped.isEmpty)
        #expect(zip(tenOffsets, tenOffsets.dropFirst()).filter { $1 - $0 == 1 }.count == 1)

        let fourteen = assign(days: 14, long: 4, paradigm: paradigm, target: race(ultra))
        let fourteenOffsets = longOffsets(fourteen)
        #expect(fourteenOffsets.count == 4)
        #expect(zip(fourteenOffsets, fourteenOffsets.dropFirst()).filter { $1 - $0 == 1 }.count <= 2)
    }

    @Test("a long run that would exceed the cap is dropped as spacing when no other day is left")
    func pairCapDrops() {
        var paradigm = TrainingParadigm.polarized8020
        paradigm.maxBackToBackLongRunPairsPerMicro = [7: 0]
        let avail = RunAvailability(slots: [.monday: [.morning], .tuesday: [.morning]])
        let result = DayAssigner(paradigm: paradigm).assign(
            micro: day(0)...day(6), availability: avail, hardCount: 0, longCount: 2, targetRace: race(ultra), calendar: calendar
        )
        #expect(longOffsets(result) == [0])
        #expect(result.dropped.map(\.reason) == [.spacing])
    }

    @Test("without a target race, or with a marathon, the pair cap is ignored and spacing applies")
    func noUltraNoCap() {
        var paradigm = TrainingParadigm.polarized8020
        paradigm.maxBackToBackLongRunPairsPerMicro = [7: 0]
        #expect(longOffsets(assign(days: 7, long: 2, paradigm: paradigm, target: nil)) == [0, 2])
        #expect(longOffsets(assign(days: 7, long: 2, paradigm: .polarized8020, target: nil)) == [0, 2])
    }

    @Test("hard sessions keep their spacing and their per-micro limit for an ultra target")
    func hardUnchanged() {
        let avail = RunAvailability(slots: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, [DaySlot.morning]) }))
        let result = DayAssigner(paradigm: .polarized8020).assign(
            micro: day(0)...day(6), availability: avail, hardCount: 3, longCount: 0, targetRace: race(ultra), calendar: calendar
        )
        #expect(result.assignments.filter { [.interval, .threshold].contains($0.runType) }.count == 2)
        #expect(result.dropped.map(\.reason) == [.hardLimit])
    }
}
