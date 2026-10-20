import Foundation

/// The macro after ``LeadTimeCompromiser`` fitted it into the lead time, with what was given up.
public struct LeadTimeAdjustment: Sendable, Codable, Hashable {
    /// The macro to lay out, at most as long as the lead time. Pass it to ``CycleLayoutBuilder``.
    public var macro: MacroTemplate
    /// The changes made, in the order they were made; empty when the macro already fitted.
    public var compromises: [LeadTimeCompromise]

    /// Creates an adjustment.
    ///
    /// - Parameters:
    ///   - macro: The macro to lay out.
    ///   - compromises: The changes made to it.
    public init(macro: MacroTemplate, compromises: [LeadTimeCompromise]) {
        self.macro = macro
        self.compromises = compromises
    }
}

/// Fits a paradigm's full macro into a lead time that is shorter than it, and reports what was
/// given up (MVP5-115).
///
/// The macro is the full-length ``MacroTemplate`` the caller built for the paradigm. When it is
/// longer than the lead time, the steps below run in order, each only while the macro is still too
/// long:
/// 1. The conditioning phase (``CyclePhase/conditioning``) is dropped. It is in the plan only if
///    ``PlanPreferences/includeConditioning`` is `true`, so dropping it reports an overridden
///    preference.
/// 2. The structural phase (``CyclePhase/structural``) is dropped.
/// 3. The paradigm's ``TrainingParadigm/shortenablePhase`` (`.specific` for triphasic, `.peak` for
///    polarized) is shortened, the earliest such block first, down to ``minimumShortenedMicros``.
/// 4. The oldest remaining blocks are trimmed, as ``CycleLayoutBuilder`` would, but the taper and
///    the shortenable phase stay.
///
/// The taper (the `.taper` and `.race` phases) is never shortened. When the taper and the shortest
/// allowed shortenable phase do not fit, ``adjust(_:paradigm:leadTimeDays:microLengthDays:preferences:)``
/// throws ``LeadTimeError/leadTimeTooShort(availableMicros:requiredMicros:)``. Without
/// conditioning in the preferences, conditioning blocks are removed whatever the lead time, and
/// that is not a compromise.
public struct LeadTimeCompromiser: Sendable, Hashable {
    /// The fewest micros the shortenable phase is cut to, in total across its blocks (or its own
    /// length, if that is shorter). Never negative.
    public var minimumShortenedMicros: Int

    /// Creates a compromiser.
    ///
    /// - Parameter minimumShortenedMicros: The fewest micros the shortenable phase is cut to;
    ///   defaults to 1. A negative value is raised to 0.
    public init(minimumShortenedMicros: Int = 1) {
        self.minimumShortenedMicros = max(minimumShortenedMicros, 0)
    }

    /// Fits `macro` into the lead time.
    ///
    /// Only whole micros count: the lead time is divided by the micro length and the remainder is
    /// not planned. Every micro is taken to have `microLengthDays`, whatever a block's own pattern
    /// says.
    ///
    /// - Parameters:
    ///   - macro: The paradigm's full macro, oldest block first.
    ///   - paradigm: Names the phase to shorten (``TrainingParadigm/shortenablePhase``).
    ///   - leadTimeDays: The days from the plan's start to race day, inclusive; not negative.
    ///   - microLengthDays: The length of a micro in days (7, 10 or 14); above zero.
    ///   - preferences: Whether the athlete wants conditioning (``PlanPreferences/includeConditioning``).
    /// - Returns: The macro to lay out and the compromises made, empty if nothing was cut for
    ///   length.
    /// - Throws: ``LeadTimeError`` for a bad micro length or lead time, or a lead time too short
    ///   for even the taper and the shortest shortenable phase.
    public func adjust(
        _ macro: MacroTemplate,
        paradigm: TrainingParadigm,
        leadTimeDays: Int,
        microLengthDays: Int,
        preferences: PlanPreferences
    ) throws -> LeadTimeAdjustment {
        guard microLengthDays > 0 else { throw LeadTimeError.invalidMicroLength }
        guard leadTimeDays >= 0 else { throw LeadTimeError.negativeLeadTime }
        let available = leadTimeDays / microLengthDays

        var blocks = macro.mesoBlocks.filter { $0.microCount > 0 }
        if !preferences.includeConditioning {
            blocks.removeAll { $0.phase == .conditioning }
        }
        let shortenable = paradigm.shortenablePhase.flatMap { $0 == .taper || $0 == .race ? nil : $0 }

        let taperMicros = Self.micros(in: blocks) { Self.isTaper($0) }
        let shortenableMicros = shortenable.map { phase in min(minimumShortenedMicros, Self.micros(in: blocks) { $0 == phase }) } ?? 0
        guard available >= taperMicros + shortenableMicros else {
            throw LeadTimeError.leadTimeTooShort(availableMicros: available, requiredMicros: taperMicros + shortenableMicros)
        }

        var compromises: [LeadTimeCompromise] = []
        func total() -> Int { blocks.reduce(0) { $0 + $1.microCount } }
        func reason() -> LeadTimeCompromise.Reason { .leadTimeTooShort(availableMicros: available, neededMicros: total()) }

        for phase in [CyclePhase.conditioning, .structural] where total() > available && phase != shortenable {
            guard blocks.contains(where: { $0.phase == phase }) else { continue }
            compromises.append(LeadTimeCompromise(action: .phaseDropped(phase), reason: reason()))
            blocks.removeAll { $0.phase == phase }
        }

        if let shortenable, total() > available {
            let before = Self.micros(in: blocks) { $0 == shortenable }
            let cut = min(total() - available, before - shortenableMicros)
            if cut > 0 {
                let after = before - cut
                compromises.append(LeadTimeCompromise(action: .phaseShortened(shortenable, fromMicros: before, toMicros: after), reason: reason()))
                var remaining = cut
                for index in blocks.indices where blocks[index].phase == shortenable && remaining > 0 {
                    let taken = min(remaining, blocks[index].microCount)
                    blocks[index].microCount -= taken
                    remaining -= taken
                }
            }
        }

        for index in blocks.indices where total() > available {
            let block = blocks[index]
            guard !Self.isTaper(block.phase), block.phase != shortenable else { continue }
            let to = max(block.microCount - (total() - available), 0)
            compromises.append(LeadTimeCompromise(action: .oldestPhaseTrimmed(block.phase, fromMicros: block.microCount, toMicros: to), reason: reason()))
            blocks[index].microCount = to
        }

        return LeadTimeAdjustment(
            macro: MacroTemplate(name: macro.name, mesoBlocks: blocks.filter { $0.microCount > 0 }),
            compromises: compromises
        )
    }

    private static func isTaper(_ phase: CyclePhase) -> Bool {
        phase == .taper || phase == .race
    }

    private static func micros(in blocks: [MacroTemplate.MesoBlock], where matches: (CyclePhase) -> Bool) -> Int {
        blocks.filter { matches($0.phase) }.reduce(0) { $0 + $1.microCount }
    }
}
