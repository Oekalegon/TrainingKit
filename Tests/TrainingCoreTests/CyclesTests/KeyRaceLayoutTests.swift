import Foundation
import Testing
@testable import TrainingCore

@Suite("KeyRaceLayout")
struct KeyRaceLayoutTests {
    let athlete = AthleteProfile.fixture()
    let primaryDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = athlete.timeZone
        return cal
    }

    /// Four base micros, four build micros and a two-micro taper: with "3:1" the roles are
    /// build, build, build, recovery, build, build, build, recovery, taper, taper.
    private let macro = MacroTemplate(name: "Test Block", mesoBlocks: [
        MacroTemplate.MesoBlock(phase: .base, microCount: 4),
        MacroTemplate.MesoBlock(phase: .build, microCount: 4),
        MacroTemplate.MesoBlock(phase: .taper, microCount: 2),
    ])

    private func meso(days: Int) -> MesocycleTemplate {
        MesocycleTemplate(name: "3:1", microRoles: [.build, .build, .build, .recovery], microLengthDays: days)
    }

    private func primary() -> Race { Race(name: "Goal", date: primaryDate, priority: .primary) }

    private func start(days: Int) -> Date {
        calendar.date(byAdding: .day, value: -(10 * days - 1), to: calendar.startOfDay(for: primaryDate))!
    }

    /// A race `offset` days into micro `index` of the exact 10-micro layout.
    private func race(_ priority: RacePriority, micro index: Int, day offset: Int = 1, days: Int = 7) -> Race {
        let date = calendar.date(byAdding: .day, value: index * days + offset, to: start(days: days))!
        return Race(name: "Race \(index)", date: date, priority: priority)
    }

    private func roles(_ races: [Race], days: Int = 7, config: KeyRaceLayout = KeyRaceLayout()) -> KeyRaceMicrocycles {
        config.microcycles(from: start(days: days), to: primary(), races: races, macro: macro, meso: meso(days: days), athlete: athlete)
    }

    private let base: [MicroLoadRole] = [.build, .build, .build, .recovery, .build, .build, .build, .recovery, .taper, .taper]

    @Test("without other races the layout is the primary layout, with the race micro in the taper")
    func primaryOnly() {
        let result = roles([])
        #expect(result.micros.map(\.loadRole) == base)
        #expect(result.adjustments.isEmpty)
        let plain = CycleLayoutBuilder().microcycles(from: start(days: 7), to: primary(), macro: macro, meso: meso(days: 7), athlete: athlete)
        #expect(result.micros == plain)
        #expect(result.micros.last?.dateRange.upperBound == calendar.startOfDay(for: primaryDate))
    }

    @Test("a secondary race mid-block tapers its micro and recovers the next, keeping phases and ranges")
    func secondaryMidBlock() {
        let secondary = race(.secondary, micro: 5)
        let result = roles([secondary])
        var expected = base
        expected[5] = .taper
        expected[6] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
        #expect(result.adjustments == [KeyRaceAdjustment(raceID: secondary.id, outcome: .applied(taperMicros: 1, recoveryMicros: 1))])
        let plain = roles([])
        #expect(result.micros.map(\.dateRange) == plain.micros.map(\.dateRange))
        #expect(result.micros.map(\.phase) == plain.micros.map(\.phase))
    }

    @Test("a race on the first day of a micro makes that micro the recovery and tapers the one before")
    func firstDayOfMicro() {
        let secondary = race(.secondary, micro: 5, day: 0)
        let result = roles([secondary])
        var expected = base
        expected[4] = .taper
        expected[5] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
        #expect(result.adjustments.first?.outcome == .applied(taperMicros: 1, recoveryMicros: 1))
    }

    @Test("the taper and recovery lengths are counted in micros")
    func configuredLengths() {
        let secondary = race(.secondary, micro: 5)
        let result = roles([secondary], config: KeyRaceLayout(secondaryTaperMicros: 2, secondaryRecoveryMicros: 2))
        var expected = base
        expected[4] = .taper
        expected[5] = .taper
        expected[6] = .recovery
        expected[7] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
        #expect(result.adjustments.first?.outcome == .applied(taperMicros: 2, recoveryMicros: 2))
    }

    @Test("zero or negative lengths change no roles")
    func zeroLengths() {
        let result = roles([race(.secondary, micro: 5)], config: KeyRaceLayout(secondaryTaperMicros: -1, secondaryRecoveryMicros: 0))
        #expect(result.micros.map(\.loadRole) == base)
        #expect(result.adjustments.first?.outcome == .applied(taperMicros: 0, recoveryMicros: 0))
    }

    @Test("a tertiary race, another primary race or the primary race again changes nothing and is not reported")
    func tertiaryChangesNothing() {
        let primaryAgain = primary()
        let races = [race(.tertiary, micro: 5), race(.primary, micro: 2), primaryAgain]
        let result = KeyRaceLayout().microcycles(from: start(days: 7), to: primaryAgain, races: races, macro: macro, meso: meso(days: 7), athlete: athlete)
        #expect(result.micros.map(\.loadRole) == base)
        #expect(result.adjustments.isEmpty)
    }

    @Test("a taper that reaches before the start of the layout is shortened")
    func taperShortenedAtStart() {
        let secondary = race(.secondary, micro: 0)
        let result = roles([secondary], config: KeyRaceLayout(secondaryTaperMicros: 3, secondaryRecoveryMicros: 1))
        #expect(result.micros.map(\.loadRole).prefix(2) == [.taper, .recovery])
        #expect(result.adjustments.first?.outcome == .applied(taperMicros: 1, recoveryMicros: 1))
    }

    @Test("two close secondary races: the later taper takes the earlier recovery")
    func twoCloseRaces() {
        let first = race(.secondary, micro: 4)
        let second = race(.secondary, micro: 5)
        // Given out of order: the result is in date order.
        let result = roles([second, first])
        var expected = base
        expected[4] = .taper
        expected[5] = .taper
        expected[6] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
        #expect(result.adjustments == [
            KeyRaceAdjustment(raceID: first.id, outcome: .applied(taperMicros: 1, recoveryMicros: 0)),
            KeyRaceAdjustment(raceID: second.id, outcome: .applied(taperMicros: 1, recoveryMicros: 1)),
        ])
    }

    @Test("a later race's longer taper is cut where the earlier race's taper ends")
    func laterTaperCut() {
        let first = race(.secondary, micro: 4)
        let second = race(.secondary, micro: 5)
        let result = roles([first, second], config: KeyRaceLayout(secondaryTaperMicros: 2, secondaryRecoveryMicros: 1))
        #expect(result.adjustments.map(\.outcome) == [
            .applied(taperMicros: 2, recoveryMicros: 0),
            .applied(taperMicros: 1, recoveryMicros: 1),
        ])
    }

    @Test("two races in the same micro: the later one is skipped")
    func sameMicro() {
        let first = race(.secondary, micro: 5, day: 1)
        let second = race(.secondary, micro: 5, day: 4)
        let result = roles([first, second])
        #expect(result.adjustments.map(\.outcome) == [.applied(taperMicros: 1, recoveryMicros: 1), .skipped(.tooCloseToEarlierRace)])
        var expected = base
        expected[5] = .taper
        expected[6] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
    }

    @Test("a race in the primary taper is skipped, and a recovery does not run into it")
    func primaryTaper() {
        let inTaper = race(.secondary, micro: 8)
        let onPrimaryDay = Race(name: "Same day", date: primaryDate, priority: .secondary)
        let before = race(.secondary, micro: 7)
        let result = roles([inTaper, onPrimaryDay, before])
        #expect(result.adjustments.map(\.outcome) == [.applied(taperMicros: 1, recoveryMicros: 0), .skipped(.insidePrimaryTaper), .skipped(.insidePrimaryTaper)])
        #expect(result.micros.suffix(2).map(\.loadRole) == [.taper, .taper])
        #expect(result.micros[7].loadRole == .taper)
    }

    @Test("races before the start or after the primary race are skipped")
    func outsideWindow() {
        let early = Race(name: "Early", date: calendar.date(byAdding: .day, value: -3, to: start(days: 7))!, priority: .secondary)
        let late = Race(name: "Late", date: calendar.date(byAdding: .day, value: 3, to: primaryDate)!, priority: .secondary)
        let result = roles([early, late])
        #expect(result.micros.map(\.loadRole) == base)
        #expect(result.adjustments.map(\.outcome) == [.skipped(.outsideLayout), .skipped(.outsideLayout)])
    }

    @Test("the same holds for micros of 7, 10 and 14 days, for a last-day and a first-day race", arguments: [7, 10, 14])
    func microLengths(days: Int) {
        let secondary = race(.secondary, micro: 5, day: days - 1, days: days)
        let result = roles([secondary], days: days)
        var expected = base
        expected[5] = .taper
        expected[6] = .recovery
        #expect(result.micros.map(\.loadRole) == expected)
        #expect(result.micros.allSatisfy { calendar.dateComponents([.day], from: $0.dateRange.lowerBound, to: $0.dateRange.upperBound).day == days - 1 })

        let firstDay = race(.secondary, micro: 5, day: 0, days: days)
        let first = roles([firstDay], days: days)
        #expect(first.micros[4].loadRole == .taper)
        #expect(first.micros[5].loadRole == .recovery)
    }

    @Test("layout gives the cycle hierarchy with the adjusted roles, targeting only the primary race")
    func cycles() {
        let secondary = race(.secondary, micro: 5)
        let result = KeyRaceLayout().layout(from: start(days: 7), to: primary(), races: [secondary], macro: macro, meso: meso(days: 7), athlete: athlete)
        let micros = result.cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        #expect(micros.count == 10)
        #expect(micros[5].loadRole == .taper)
        #expect(micros[6].loadRole == .recovery)
        #expect(result.cycles.filter { $0.targetRaceID != nil }.allSatisfy { $0.level != .micro })
        #expect(result.cycles.first { $0.level == .macro }?.targetRaceID != nil)
        #expect(result.adjustments.count == 1)
    }

    @Test("a start after the primary race gives nothing")
    func noLayout() {
        let late = calendar.date(byAdding: .day, value: 5, to: primaryDate)!
        let result = KeyRaceLayout().layout(from: late, to: primary(), races: [], macro: macro, meso: meso(days: 7), athlete: athlete)
        #expect(result.cycles.isEmpty)
        #expect(result.adjustments.isEmpty)
    }

    @Test("value types round-trip through Codable")
    func codable() throws {
        let config = KeyRaceLayout(secondaryTaperMicros: 2, secondaryRecoveryMicros: 3)
        #expect(try JSONDecoder().decode(KeyRaceLayout.self, from: JSONEncoder().encode(config)) == config)
        let adjustment = KeyRaceAdjustment(raceID: UUID(), outcome: .skipped(.insidePrimaryTaper))
        #expect(try JSONDecoder().decode(KeyRaceAdjustment.self, from: JSONEncoder().encode(adjustment)) == adjustment)
    }
}
