import Foundation

/// The settings ``PlanAdjuster`` changes to make a plan proposal safer, and a
/// ``PlanCandidateProvider`` honours when it builds the proposal (MVP5-120).
///
/// The adjuster never edits workouts itself. It hands the provider a set of levers and the provider
/// rebuilds the plan with them applied. ``none`` is the plan as first asked for. Days and micros are
/// identified by their start of day, in the timezone of the plan's metrics. `volumeScales` has date
/// keys, so it encodes as a flat array of alternating keys and values, not as a JSON object.
public struct PlanLevers: Sendable, Codable, Hashable {
    /// The factor on the volume of a micro, by the start of the micro: 0.9 asks for 90 % of the
    /// volume the curve gave it. A micro that is not listed keeps 1.
    public var volumeScales: [Date: Double]
    /// The micros, by start, to turn into a recovery micro (reduced load), whatever their role was.
    public var downWeeks: Set<Date>
    /// The days whose hard session is replaced by an easy run.
    public var easedDays: Set<Date>
    /// The days whose session is left out altogether.
    public var droppedDays: Set<Date>

    /// No change: the plan as first asked for.
    public static let none = PlanLevers()

    /// Creates a set of levers.
    ///
    /// - Parameters:
    ///   - volumeScales: The factor on the volume per micro start; defaults to none.
    ///   - downWeeks: The micro starts to turn into recovery micros; defaults to none.
    ///   - easedDays: The days whose hard session becomes easy; defaults to none.
    ///   - droppedDays: The days whose session is dropped; defaults to none.
    public init(
        volumeScales: [Date: Double] = [:],
        downWeeks: Set<Date> = [],
        easedDays: Set<Date> = [],
        droppedDays: Set<Date> = []
    ) {
        self.volumeScales = volumeScales
        self.downWeeks = downWeeks
        self.easedDays = easedDays
        self.droppedDays = droppedDays
    }

    /// The volume factor of the micro starting on `microStart`: the listed factor, or 1.
    ///
    /// - Parameter microStart: The first day of the micro.
    public func volumeScale(forMicro microStart: Date) -> Double {
        volumeScales[microStart] ?? 1
    }

    /// These levers with `adjustment` applied; the levers themselves are not changed.
    ///
    /// - Parameter adjustment: The change to make.
    public func applying(_ adjustment: PlanAdjustment) -> PlanLevers {
        var result = self
        switch adjustment {
        case .lowerVolume(let microStart, let scale): result.volumeScales[microStart] = scale
        case .downWeek(let microStart): result.downWeeks.insert(microStart)
        case .easeSession(let day): result.easedDays.insert(day)
        case .dropSession(let day): result.droppedDays.insert(day)
        }
        return result
    }
}
