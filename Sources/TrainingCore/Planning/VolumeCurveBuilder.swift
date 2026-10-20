import Foundation

/// Sets a volume target for every micro of a laid-out plan: the volume curve of the plan generator.
///
/// Volumes are given **per 7 days** and scaled by each micro's length, so a 14-day micro holds
/// twice the weekly volume and 7-, 10- and 14-day micros read alike. From `starting` to `peak`:
/// - **Build micros** climb in equal steps from the starting volume at the first build micro to
///   the peak at the last one (a single build micro gets the peak). Recovery micros between them do
///   not add a step.
/// - **Recovery micros** hold ``recoveryLoadFraction`` of the preceding build micro (the first
///   build micro for a recovery that comes before any build; the starting volume if there is none).
/// - **Taper micros** step down linearly from ``taperStartFraction`` to ``taperEndFraction`` of the
///   peak (the last build micro's volume); a single taper micro gets the midpoint.
/// - **The race micro**, the last micro when its role is ``MicroLoadRole/taper`` (as
///   ``CycleLayoutBuilder`` lays it out) or ``MicroLoadRole/race`` (older stored plans), gets
///   ``raceFraction`` of the peak and is not part of the taper ramp.
///
/// A plan with no build micro has no ramp: recovery micros then hold the fraction of the starting
/// volume, and taper and race micros the fraction of the peak.
///
/// The curve is the plan before the guardrails: the generator evaluates the plan it makes from it
/// and lowers micros where the guardrails ask, and reports the volume it reached. It does not
/// read ``PlanPreferences/maxWeeklyVolume``; the caller passes the peak, capped by that limit if
/// the athlete set one. The fractions are design defaults, not training prescriptions, and can be
/// changed per builder.
public struct VolumeCurveBuilder: Sendable, Hashable {
    /// A recovery micro's volume relative to the preceding build micro; defaults to 0.6, like
    /// ``MesocycleTemplate/recoveryLoadFraction``.
    public var recoveryLoadFraction: Double
    /// The first taper micro's volume relative to the peak; defaults to 0.7.
    public var taperStartFraction: Double
    /// The last taper micro's volume relative to the peak; defaults to 0.5.
    public var taperEndFraction: Double
    /// The race micro's volume relative to the peak; defaults to 0.3.
    public var raceFraction: Double

    /// Creates a volume curve builder.
    ///
    /// - Parameters:
    ///   - recoveryLoadFraction: A recovery micro's volume relative to the preceding build micro;
    ///     defaults to 0.6.
    ///   - taperStartFraction: The first taper micro's volume relative to the peak; defaults to 0.7.
    ///   - taperEndFraction: The last taper micro's volume relative to the peak; defaults to 0.5.
    ///   - raceFraction: The race micro's volume relative to the peak; defaults to 0.3.
    public init(recoveryLoadFraction: Double = 0.6, taperStartFraction: Double = 0.7, taperEndFraction: Double = 0.5, raceFraction: Double = 0.3) {
        self.recoveryLoadFraction = recoveryLoadFraction
        self.taperStartFraction = taperStartFraction
        self.taperEndFraction = taperEndFraction
        self.raceFraction = raceFraction
    }

    /// The volume target of every micro.
    ///
    /// - Parameters:
    ///   - micros: The micros of the plan, e.g. from ``CycleLayoutBuilder``; any order.
    ///   - starting: The volume per 7 days of the first build micro.
    ///   - peak: The volume per 7 days of the last build micro, in the same measure as `starting`
    ///     and at least as large.
    /// - Returns: One target per micro, in date order, in the measure of `starting`. Empty for no micros.
    /// - Throws: ``VolumeCurveError`` for a mismatched measure, a peak below the start, or a
    ///   fraction that is not in 0...1 (above 0), or a taper that rises (start below end).
    public func targets(for micros: [Microcycle], starting: VolumeTarget, peak: VolumeTarget) throws -> [MicroVolumeTarget] {
        guard starting.measure == peak.measure else { throw VolumeCurveError.mismatchedMeasure }
        guard peak.amount >= starting.amount else { throw VolumeCurveError.peakBelowStart }
        let fractions = [recoveryLoadFraction, taperStartFraction, taperEndFraction, raceFraction]
        guard fractions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 }), taperStartFraction >= taperEndFraction else {
            throw VolumeCurveError.invalidFraction
        }

        let ordered = micros.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        let buildCount = ordered.filter { $0.loadRole == .build }.count
        // The micro with race day is the last one; layouts give it the taper role, older stored
        // plans the race role. Either way it gets the race fraction and is not part of the ramp.
        let raceStart = ordered.last.flatMap { $0.loadRole == .taper || $0.loadRole == .race ? $0.dateRange.lowerBound : nil }
        let taperCount = ordered.filter { $0.loadRole == .taper && $0.dateRange.lowerBound != raceStart }.count

        // The weekly volume of the build micros, in order, so recovery can refer to the last one.
        let buildWeekly = (0..<buildCount).map { index in
            buildCount == 1 ? peak.amount : starting.amount + (peak.amount - starting.amount) * Double(index) / Double(buildCount - 1)
        }
        let peakWeekly = buildWeekly.last ?? peak.amount

        var result: [MicroVolumeTarget] = []
        var buildIndex = 0
        var taperIndex = 0
        var lastBuildWeekly: Double?
        for micro in ordered {
            let weekly: Double
            switch micro.dateRange.lowerBound == raceStart ? .race : micro.loadRole {
            case .build:
                weekly = buildWeekly[buildIndex]
                buildIndex += 1
                lastBuildWeekly = weekly
            case .recovery:
                weekly = recoveryLoadFraction * (lastBuildWeekly ?? buildWeekly.first ?? starting.amount)
            case .taper:
                let fraction = taperCount == 1
                    ? (taperStartFraction + taperEndFraction) / 2
                    : taperStartFraction + (taperEndFraction - taperStartFraction) * Double(taperIndex) / Double(taperCount - 1)
                weekly = fraction * peakWeekly
                taperIndex += 1
            case .race:
                weekly = raceFraction * peakWeekly
            }
            let days = Self.lengthInDays(micro.dateRange)
            guard let target = VolumeTarget(measure: starting.measure, amount: weekly * Double(days) / 7) else {
                throw VolumeCurveError.invalidFraction
            }
            result.append(MicroVolumeTarget(microStart: micro.dateRange.lowerBound, lengthDays: days, phase: micro.phase, loadRole: micro.loadRole, target: target))
        }
        return result
    }

    /// The length of a day-granular range in whole calendar days, rounded so a daylight-saving day
    /// does not change it.
    private static func lengthInDays(_ range: ClosedRange<Date>) -> Int {
        Int((range.upperBound.timeIntervalSince(range.lowerBound) / 86_400).rounded()) + 1
    }
}
