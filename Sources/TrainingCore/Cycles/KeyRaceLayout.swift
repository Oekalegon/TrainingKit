import Foundation

/// Lays out a plan around the athlete's key races: the primary race anchors the macro, each
/// secondary race gets a mini-taper before it and a recovery after it, and tertiary races change
/// nothing.
///
/// The primary race is laid out by ``CycleLayoutBuilder``. A secondary race then changes only the
/// ``Microcycle/loadRole`` of existing micros, so no micro is added or removed and phases, meso
/// blocks and the primary taper keep their place:
/// - The micro containing race day is a `.taper` micro (there is no race role), unless race day is
///   the first day of the micro: that micro is then the first `.recovery` micro.
/// - The ``secondaryTaperMicros`` micros up to and including the micro with race day are `.taper`
///   (or, for a race on the first day of a micro, the ones just before it).
/// - The next ``secondaryRecoveryMicros`` micros are `.recovery`.
///
/// Lengths are counted in micros, so 7-, 10- and 14-day micros all work.
///
/// A secondary race that cannot be placed is skipped, and one that only partly fits gets a
/// shorter taper or recovery. Every secondary race is reported in
/// ``KeyRaceMicrocycles/adjustments``. When two secondary races are close together the earlier
/// race keeps its taper and the later race's taper wins over the earlier race's recovery.
/// Races of other priorities, and the primary race listed again, are ignored without a report.
///
/// This type does not decide how the micros are filled; it works on the micro layout only, and does
/// not depend on a training plan.
public struct KeyRaceLayout: Sendable, Codable, Hashable {
    /// How many micros a secondary race's taper spans, counting the micro with race day; defaults
    /// to 1. Negative values count as 0.
    public var secondaryTaperMicros: Int
    /// How many micros of recovery follow a secondary race; defaults to 1. Negative values count
    /// as 0.
    public var secondaryRecoveryMicros: Int

    /// Creates a key-race layout.
    ///
    /// - Parameters:
    ///   - secondaryTaperMicros: How many micros a secondary race's taper spans, counting the micro
    ///     with race day; defaults to 1.
    ///   - secondaryRecoveryMicros: How many micros of recovery follow a secondary race; defaults to 1.
    public init(secondaryTaperMicros: Int = 1, secondaryRecoveryMicros: Int = 1) {
        self.secondaryTaperMicros = secondaryTaperMicros
        self.secondaryRecoveryMicros = secondaryRecoveryMicros
    }

    /// Lays out the micros from `start` to the primary race and applies the secondary races.
    ///
    /// - Parameters:
    ///   - start: The earliest day the layout may begin; see
    ///     ``CycleLayoutBuilder/microcycles(from:to:macro:meso:athlete:)``.
    ///   - primary: The race the macro is anchored on. Its priority is not checked.
    ///   - races: The other races of the athlete, in any order. Only ``RacePriority/secondary``
    ///     races are acted on; the ones outside the laid-out days are reported as skipped.
    ///   - macro: The ordered phase/length structure to fill backward from the primary race.
    ///   - meso: The default build/recovery pattern.
    ///   - athlete: Supplies the timezone used for all day-granular boundaries.
    /// - Returns: The micros, oldest first, and one adjustment per secondary race. Both are empty
    ///   under the conditions where ``CycleLayoutBuilder/microcycles(from:to:macro:meso:athlete:)``
    ///   returns no micros.
    public func microcycles(
        from start: Date,
        to primary: Race,
        races: [Race],
        macro: MacroTemplate,
        meso: MesocycleTemplate,
        athlete: AthleteProfile
    ) -> KeyRaceMicrocycles {
        let base = CycleLayoutBuilder().microcycles(from: start, to: primary, macro: macro, meso: meso, athlete: athlete)
        return apply(to: base, primary: primary, races: races, athlete: athlete)
    }

    /// Lays out the macro, meso and micro cycles from `start` to the primary race and applies the
    /// secondary races.
    ///
    /// - Parameters: See ``microcycles(from:to:races:macro:meso:athlete:)``.
    /// - Returns: The cycles as ``CycleLayoutBuilder/layout(from:to:macro:meso:athlete:)`` returns
    ///   them (the macro and meso cycles target the primary race; secondary races have no cycle of
    ///   their own) and the adjustments.
    public func layout(
        from start: Date,
        to primary: Race,
        races: [Race],
        macro: MacroTemplate,
        meso: MesocycleTemplate,
        athlete: AthleteProfile
    ) -> KeyRaceCycles {
        let result = microcycles(from: start, to: primary, races: races, macro: macro, meso: meso, athlete: athlete)
        guard !result.micros.isEmpty else { return KeyRaceCycles(cycles: [], adjustments: []) }
        return KeyRaceCycles(cycles: CycleLayoutBuilder().cycles(from: result.micros, macro: macro, race: primary), adjustments: result.adjustments)
    }

    /// Applies the secondary races to micros that were laid out back from the primary race.
    ///
    /// - Parameters:
    ///   - micros: The micros, e.g. from ``CycleLayoutBuilder``, oldest first, the last one
    ///     containing the primary race day.
    ///   - primary: The primary race.
    ///   - races: The other races, in any order.
    ///   - athlete: Supplies the timezone used for all day-granular boundaries.
    /// - Returns: The micros with the changed load roles and one adjustment per secondary race,
    ///   in date order (races on the same day in the order given).
    public func apply(to micros: [Microcycle], primary: Race, races: [Race], athlete: AthleteProfile) -> KeyRaceMicrocycles {
        guard !micros.isEmpty else { return KeyRaceMicrocycles(micros: [], adjustments: []) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone

        let secondaries = races
            .filter { $0.priority == .secondary && $0.id != primary.id }
            .sorted { $0.date < $1.date }
        var roles = micros.map(\.loadRole)
        var adjustments: [KeyRaceAdjustment] = []

        // The primary taper is the run of taper micros at the end; nothing of a secondary race may
        // reach into it.
        var primaryTaperStart = micros.count - 1
        while primaryTaperStart > 0, roles[primaryTaperStart - 1] == .taper { primaryTaperStart -= 1 }
        // Micros up to this index are claimed by the taper of an earlier secondary race.
        var claimedThrough = -1
        // Which adjustment currently owns each recovery micro, so a later race that takes one over
        // is counted against the earlier race.
        var recoveryOwner: [Int: Int] = [:]

        let taperCount = max(0, secondaryTaperMicros)
        let recoveryCount = max(0, secondaryRecoveryMicros)

        for race in secondaries {
            let day = calendar.startOfDay(for: race.date)
            guard let index = micros.firstIndex(where: { $0.dateRange.contains(day) }) else {
                adjustments.append(KeyRaceAdjustment(raceID: race.id, outcome: .skipped(.outsideLayout)))
                continue
            }
            guard index < primaryTaperStart else {
                adjustments.append(KeyRaceAdjustment(raceID: race.id, outcome: .skipped(.insidePrimaryTaper)))
                continue
            }
            // A race on the first day of a micro starts that micro's recovery; the taper ends the
            // day before.
            let firstDay = day == micros[index].dateRange.lowerBound
            let taperEnd = firstDay ? index - 1 : index
            let recoveryStart = taperEnd + 1
            guard index > claimedThrough else {
                adjustments.append(KeyRaceAdjustment(raceID: race.id, outcome: .skipped(.tooCloseToEarlierRace)))
                continue
            }

            let taperStart = max(taperEnd - taperCount + 1, claimedThrough + 1)
            let taperIndices = taperStart <= taperEnd ? Array(taperStart...taperEnd) : []
            let recoveryEnd = min(recoveryStart + recoveryCount, primaryTaperStart)
            let recoveryIndices = recoveryStart < recoveryEnd ? Array(recoveryStart..<recoveryEnd) : []
            let position = adjustments.count
            adjustments.append(KeyRaceAdjustment(raceID: race.id, outcome: .applied(taperMicros: taperIndices.count, recoveryMicros: recoveryIndices.count)))
            for taperIndex in taperIndices {
                roles[taperIndex] = .taper
                takeOver(taperIndex, from: &recoveryOwner, in: &adjustments)
            }
            for recoveryIndex in recoveryIndices {
                roles[recoveryIndex] = .recovery
                takeOver(recoveryIndex, from: &recoveryOwner, in: &adjustments)
                recoveryOwner[recoveryIndex] = position
            }
            claimedThrough = max(claimedThrough, taperEnd)
        }

        let result = zip(micros, roles).map { micro, role in
            Microcycle(dateRange: micro.dateRange, phase: micro.phase, loadRole: role, mesoBlockIndex: micro.mesoBlockIndex)
        }
        return KeyRaceMicrocycles(micros: result, adjustments: adjustments)
    }

    /// Removes micro `index` from the recovery of the earlier race that owned it, if any.
    private func takeOver(_ index: Int, from owners: inout [Int: Int], in adjustments: inout [KeyRaceAdjustment]) {
        guard let owner = owners.removeValue(forKey: index),
              case .applied(let taper, let recovery) = adjustments[owner].outcome else { return }
        adjustments[owner].outcome = .applied(taperMicros: taper, recoveryMicros: recovery - 1)
    }
}

/// Micros laid out around the key races, with what happened to each secondary race.
public struct KeyRaceMicrocycles: Sendable, Codable, Hashable {
    /// The micros, oldest first.
    public var micros: [Microcycle]
    /// One entry per secondary race, in date order.
    public var adjustments: [KeyRaceAdjustment]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - micros: The micros, oldest first.
    ///   - adjustments: One entry per secondary race, in date order.
    public init(micros: [Microcycle], adjustments: [KeyRaceAdjustment]) {
        self.micros = micros
        self.adjustments = adjustments
    }
}

/// Cycles laid out around the key races, with what happened to each secondary race.
public struct KeyRaceCycles: Sendable, Codable, Hashable {
    /// The macro, meso and micro cycles, in the order ``CycleLayoutBuilder/layout(from:to:macro:meso:athlete:)`` gives.
    public var cycles: [TrainingCycle]
    /// One entry per secondary race, in date order.
    public var adjustments: [KeyRaceAdjustment]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - cycles: The macro, meso and micro cycles.
    ///   - adjustments: One entry per secondary race, in date order.
    public init(cycles: [TrainingCycle], adjustments: [KeyRaceAdjustment]) {
        self.cycles = cycles
        self.adjustments = adjustments
    }
}

/// What ``KeyRaceLayout`` did for one secondary race.
public struct KeyRaceAdjustment: Identifiable, Sendable, Codable, Hashable {
    /// What happened to the race.
    public enum Outcome: Sendable, Codable, Hashable {
        /// The race got a taper and a recovery, in micros; compare with the configured lengths to
        /// see whether either was shortened (down to 0) by the start of the layout, the primary
        /// taper or a neighbouring race.
        case applied(taperMicros: Int, recoveryMicros: Int)
        /// The race was not placed, for the reason given.
        case skipped(SkipReason)
    }

    /// Why a secondary race was not placed.
    public enum SkipReason: String, Sendable, Codable, Hashable, CaseIterable {
        /// Race day is before the first micro or after the primary race (which has no micro after
        /// its day).
        case outsideLayout
        /// Race day falls in the primary race's taper.
        case insidePrimaryTaper
        /// Race day is in the same micro as an earlier secondary race, or in one the earlier
        /// race's taper claims.
        case tooCloseToEarlierRace
    }

    /// The secondary race's ID.
    public var id: UUID { raceID }
    /// The secondary race this entry is about.
    public var raceID: UUID
    /// What happened to the race.
    public var outcome: Outcome

    /// Creates an adjustment.
    ///
    /// - Parameters:
    ///   - raceID: The secondary race this entry is about.
    ///   - outcome: What happened to the race.
    public init(raceID: UUID, outcome: Outcome) {
        self.raceID = raceID
        self.outcome = outcome
    }
}
