import Foundation

/// Lays out a macrocycle backwards from a race date, so the user doesn't have to place every
/// micro-cycle by hand.
///
/// The algorithm works backwards from `race.date`:
/// 1. The very last micro (the one covering race day itself) is always phase `.race`.
/// 2. Every other micro in a `.taper`-phase ``MacroTemplate/MesoBlock`` is phase `.taper`.
/// 3. Every micro in any other block cycles through `meso.microPhases` (e.g. "3:1"'s
///    `build, build, build, recovery`), restarting the pattern at each block's boundary.
/// 4. Filling continues backward through every block in `macro.mesoBlocks` until reaching `from`.
///    If `from` falls in the middle of the oldest surviving block, that block (and only that one)
///    is trimmed short rather than starting before `from`; if `from` falls so close to the race
///    that some of the oldest blocks wouldn't fit at all, they're dropped entirely instead of
///    producing a negative- or zero-length cycle — e.g. a race one week away with a multi-month
///    macro template still lays out cleanly as just the trimmed taper block plus the race micro.
///
/// In MVP 1 this is invoked directly by the user ("lay out a 3:1 block from today to this race");
/// MVP 2's plan generator calls the same builder and then fills each micro with `[PlannedActivity]`.
public struct CycleLayoutBuilder: Sendable {
    /// Creates a cycle layout builder.
    public init() {}

    /// Lays out one macrocycle, its mesocycles, and their micro-cycles from `start` through
    /// `race.date`.
    ///
    /// - Parameters:
    ///   - start: The earliest day the layout may begin, in the athlete's timezone. The actual
    ///     layout may begin later than this if `macro`'s total length is shorter than the span to
    ///     `race.date`, and a block may be trimmed or dropped if it's longer (see the type's
    ///     documentation).
    ///   - race: The race the layout tapers into; every generated cycle's `targetRaceID` is set to
    ///     `race.id` (macro and meso levels only, per ``TrainingCycle/targetRaceID``).
    ///   - macro: The ordered phase/length structure to fill backward from the race.
    ///   - meso: The repeating build/recovery pattern applied within every non-taper, non-race
    ///     block.
    ///   - athlete: Supplies the timezone used for all day-granular boundaries.
    /// - Returns: One macro-level ``TrainingCycle``, one meso-level cycle per surviving
    ///   ``MacroTemplate/MesoBlock``, and one micro-level cycle per surviving micro — parented
    ///   micro → meso → macro. Empty if `race.date` is before `start`, or if `macro` has no blocks.
    public func layout(
        from start: Date,
        to race: Race,
        macro: MacroTemplate,
        meso: MesocycleTemplate,
        athlete: AthleteProfile
    ) -> [TrainingCycle] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        let startDay = calendar.startOfDay(for: start)
        let raceDay = calendar.startOfDay(for: race.date)

        guard raceDay >= startDay, !macro.mesoBlocks.isEmpty else {
            Logging.series.warning("CycleLayoutBuilder.layout(from:to:macro:meso:athlete:) called with race date before start, or an empty macro template; returning no cycles")
            return []
        }

        let micros = trimmed(micros: microSlots(macro: macro, meso: meso, raceDay: raceDay, calendar: calendar), toStartOn: startDay)
        guard !micros.isEmpty else { return [] }

        return cycles(from: micros, macro: macro, race: race)
    }

    /// One micro-cycle's phase, parent block, and date range before trimming.
    private struct MicroSlot {
        let blockIndex: Int
        let phase: CyclePhase
        let dateRange: ClosedRange<Date>
    }

    /// Generates every micro implied by `macro`, working backward from `raceDay`, then returns
    /// them in chronological order.
    private func microSlots(macro: MacroTemplate, meso: MesocycleTemplate, raceDay: Date, calendar: Calendar) -> [MicroSlot] {
        var slots: [MicroSlot] = []
        var cursorEnd = raceDay

        for blockIndex in macro.mesoBlocks.indices.reversed() {
            let block = macro.mesoBlocks[blockIndex]
            guard block.microCount > 0 else { continue }

            for positionFromBlockEnd in 0..<block.microCount {
                let positionInBlock = block.microCount - 1 - positionFromBlockEnd
                let lowerBound = calendar.date(byAdding: .day, value: -(meso.microLengthDays - 1), to: cursorEnd)!
                let phase = phase(forPositionInBlock: positionInBlock, block: block, meso: meso, isRaceMicro: slots.isEmpty)
                slots.append(MicroSlot(blockIndex: blockIndex, phase: phase, dateRange: lowerBound...cursorEnd))
                cursorEnd = calendar.date(byAdding: .day, value: -meso.microLengthDays, to: cursorEnd)!
            }
        }

        return slots.reversed()
    }

    private func phase(forPositionInBlock position: Int, block: MacroTemplate.MesoBlock, meso: MesocycleTemplate, isRaceMicro: Bool) -> CyclePhase {
        guard !isRaceMicro else { return .race }
        guard block.phase != .taper, block.phase != .race else { return block.phase }
        guard !meso.microPhases.isEmpty else { return block.phase }
        return meso.microPhases[position % meso.microPhases.count]
    }

    /// Drops any micro entirely before `startDay`, and clamps the one micro that straddles it —
    /// the "trim the oldest block" behavior described in the type's documentation.
    private func trimmed(micros: [MicroSlot], toStartOn startDay: Date) -> [MicroSlot] {
        micros.compactMap { slot in
            guard slot.dateRange.upperBound >= startDay else { return nil }
            guard slot.dateRange.lowerBound < startDay else { return slot }
            return MicroSlot(blockIndex: slot.blockIndex, phase: slot.phase, dateRange: startDay...slot.dateRange.upperBound)
        }
    }

    /// Builds the macro/meso/micro `TrainingCycle` hierarchy from the surviving, chronologically
    /// ordered micro slots.
    private func cycles(from micros: [MicroSlot], macro: MacroTemplate, race: Race) -> [TrainingCycle] {
        let macroID = UUID()
        var result: [TrainingCycle] = []
        var weekNumber = 0

        var groupStart = 0
        var groupIndex = 0
        while groupStart < micros.count {
            let blockIndex = micros[groupStart].blockIndex
            var groupEnd = groupStart
            while groupEnd + 1 < micros.count, micros[groupEnd + 1].blockIndex == blockIndex {
                groupEnd += 1
            }
            let group = micros[groupStart...groupEnd]
            groupIndex += 1

            let mesoID = UUID()
            let mesoName = "\(macro.name) Meso \(groupIndex)"
            result.append(
                TrainingCycle(
                    id: mesoID,
                    level: .meso,
                    phase: macro.mesoBlocks[blockIndex].phase,
                    name: mesoName,
                    dateRange: group.first!.dateRange.lowerBound...group.last!.dateRange.upperBound,
                    parentID: macroID,
                    targetRaceID: race.id
                )
            )

            for slot in group {
                weekNumber += 1
                result.append(
                    TrainingCycle(
                        level: .micro,
                        phase: slot.phase,
                        name: "\(macro.name) Week \(weekNumber)",
                        dateRange: slot.dateRange,
                        parentID: mesoID
                    )
                )
            }

            groupStart = groupEnd + 1
        }

        let macroCycle = TrainingCycle(
            id: macroID,
            level: .macro,
            phase: macro.mesoBlocks[micros.first!.blockIndex].phase,
            name: macro.name,
            dateRange: micros.first!.dateRange.lowerBound...micros.last!.dateRange.upperBound,
            targetRaceID: race.id
        )
        result.insert(macroCycle, at: 0)

        return result
    }
}
