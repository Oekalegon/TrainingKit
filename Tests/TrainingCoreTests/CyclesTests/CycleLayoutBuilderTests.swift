import Foundation
import Testing
@testable import TrainingCore

@Suite("CycleLayoutBuilder")
struct CycleLayoutBuilderTests {
    let athlete = AthleteProfile.fixture()
    let builder = CycleLayoutBuilder()
    let raceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = athlete.timeZone
        return cal
    }

    private var macro: MacroTemplate {
        MacroTemplate(name: "Test Block", mesoBlocks: [
            MacroTemplate.MesoBlock(phase: .base, microCount: 4),
            MacroTemplate.MesoBlock(phase: .build, microCount: 4),
            MacroTemplate.MesoBlock(phase: .taper, microCount: 2),
        ])
    }
    private let meso = MesocycleTemplate.threeToOne // [.build, .build, .build, .recovery], 7-day micros

    private func race() -> Race {
        Race(name: "Goal Marathon", date: raceDate, priority: .a)
    }

    /// The `start` that exactly fits the whole macro (10 micros × 7 days) ending on race day, with
    /// no trimming needed.
    private func exactStart(raceDay: Date) -> Date {
        let totalDays = 10 * meso.microLengthDays
        return calendar.date(byAdding: .day, value: -(totalDays - 1), to: raceDay)!
    }

    @Test("a full layout with room to spare has no gaps, no overlaps, and correct phases")
    func fullLayout() {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)
        let start = exactStart(raceDay: raceDay)

        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        let macros = cycles.filter { $0.level == .macro }
        let mesos = cycles.filter { $0.level == .meso }
        let micros = cycles.filter { $0.level == .micro }
        #expect(macros.count == 1)
        #expect(mesos.count == 3)
        #expect(micros.count == 10)

        let sortedMicros = micros.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        #expect(sortedMicros.first?.dateRange.lowerBound == start)
        #expect(sortedMicros.last?.dateRange.upperBound == raceDay)
        for (earlier, later) in zip(sortedMicros, sortedMicros.dropFirst()) {
            let expectedNextStart = calendar.date(byAdding: .day, value: 1, to: earlier.dateRange.upperBound)!
            #expect(later.dateRange.lowerBound == expectedNextStart)
        }

        // The last micro overall is always the race micro; the one before it (still within the
        // taper block) is .taper rather than cycling the build/recovery pattern.
        #expect(sortedMicros.last?.phase == .race)
        #expect(sortedMicros[sortedMicros.count - 2].phase == .taper)

        // Base and build blocks each restart the 3:1 pattern at their own boundary.
        #expect(sortedMicros[0..<4].map(\.phase) == [.build, .build, .build, .recovery])
        #expect(sortedMicros[4..<8].map(\.phase) == [.build, .build, .build, .recovery])

        let macroCycle = macros[0]
        #expect(macroCycle.dateRange == start...raceDay)
        #expect(macroCycle.targetRaceID == race.id)
        for meso in mesos {
            #expect(meso.parentID == macroCycle.id)
            #expect(meso.targetRaceID == race.id)
        }
        for micro in micros {
            #expect(mesos.contains { $0.id == micro.parentID })
            #expect(micro.targetRaceID == nil)
        }
    }

    @Test("start falling mid-meso trims only the oldest meso, not the whole layout")
    func trimsOldestMeso() {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)
        let exact = exactStart(raceDay: raceDay)
        let start = calendar.date(byAdding: .day, value: 3, to: exact)!

        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        let micros = cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        #expect(micros.count == 10)
        #expect(micros.first?.dateRange.lowerBound == start)
        let firstMicroDaySpan = micros.first.flatMap {
            calendar.dateComponents([.day], from: $0.dateRange.lowerBound, to: $0.dateRange.upperBound).day
        }
        #expect(firstMicroDaySpan == 3) // 4 days inclusive, shorter than the usual 7
    }

    @Test("a race less than one meso away drops earlier blocks entirely rather than going negative")
    func raceLessThanOneMesoAway() {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)
        let start = calendar.date(byAdding: .day, value: -3, to: raceDay)!

        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        let micros = cycles.filter { $0.level == .micro }
        let mesos = cycles.filter { $0.level == .meso }
        #expect(micros.count == 1)
        #expect(micros.first?.phase == .race)
        #expect(micros.first?.dateRange == start...raceDay)
        #expect(mesos.count == 1)
        #expect(mesos.first?.phase == .taper)
        for cycle in cycles {
            #expect(cycle.dateRange.lowerBound <= cycle.dateRange.upperBound)
        }
    }

    @Test("start exactly on race day produces a single one-day race micro")
    func startEqualsRaceDay() {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)

        let cycles = builder.layout(from: raceDay, to: race, macro: macro, meso: meso, athlete: athlete)

        let micros = cycles.filter { $0.level == .micro }
        #expect(micros.count == 1)
        #expect(micros.first?.dateRange == raceDay...raceDay)
        #expect(micros.first?.phase == .race)
    }

    @Test("a race date before start returns no cycles")
    func raceBeforeStartReturnsEmpty() {
        let race = race()
        let start = calendar.date(byAdding: .day, value: 1, to: raceDate)!

        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        #expect(cycles.isEmpty)
    }

    @Test("an empty macro template returns no cycles")
    func emptyMacroReturnsEmpty() {
        let emptyMacro = MacroTemplate(name: "Empty", mesoBlocks: [])

        let cycles = builder.layout(from: raceDate, to: race(), macro: emptyMacro, meso: meso, athlete: athlete)

        #expect(cycles.isEmpty)
    }

    @Test("the layout satisfies CycleStore's nesting and overlap invariants")
    func layoutSatisfiesCycleStoreInvariants() async throws {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)
        let start = exactStart(raceDay: raceDay)

        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        let store = InMemoryStore()
        try await store.upsert(cycles)
    }

    @Test("microcycles(from:to:macro:meso:athlete:) previews the same weeks layout(...) commits")
    func microcyclesMatchesLayout() {
        let race = race()
        let raceDay = calendar.startOfDay(for: raceDate)
        let start = exactStart(raceDay: raceDay)

        let micros = builder.microcycles(from: start, to: race, macro: macro, meso: meso, athlete: athlete)
        let cycles = builder.layout(from: start, to: race, macro: macro, meso: meso, athlete: athlete)
        let microCycles = cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }

        #expect(micros.count == 10)
        #expect(micros.map(\.dateRange) == microCycles.map(\.dateRange))
        #expect(micros.map(\.phase) == microCycles.map(\.phase))
        #expect(micros.last?.phase == .race)
        #expect(micros.map(\.id) == micros.map(\.dateRange.lowerBound))
    }

    @Test("microcycles(from:to:macro:meso:athlete:) is empty when race is before start")
    func microcyclesEmptyWhenRaceBeforeStart() {
        let race = race()
        let start = calendar.date(byAdding: .day, value: 1, to: raceDate)!

        let micros = builder.microcycles(from: start, to: race, macro: macro, meso: meso, athlete: athlete)

        #expect(micros.isEmpty)
    }
}
