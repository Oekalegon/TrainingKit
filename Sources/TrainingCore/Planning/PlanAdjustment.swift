import Foundation

/// One change ``PlanAdjuster`` can make to a proposal, each answering a kind of ``PlanFinding``.
///
/// Applied to ``PlanLevers`` with ``PlanLevers/applying(_:)``. The adjuster tries them gentlest first:
/// lower volume, then down-week, then ease a session, then drop it.
public enum PlanAdjustment: Sendable, Codable, Hashable {
    /// Ask for `scale` times the curve's volume in the micro starting on `microStart` (1 is unchanged,
    /// 0.9 is 10 % less). Answers a low TSB, a high strain, a long-run jump.
    case lowerVolume(microStart: Date, scale: Double)
    /// Turn the micro starting on `microStart` into a recovery micro. Answers a low TSB, a high strain.
    case downWeek(microStart: Date)
    /// Replace the hard session on `day` by an easy run. Answers too many or too close hard sessions,
    /// and a high monotony.
    case easeSession(day: Date)
    /// Leave out the session on `day`. Answers too many or too close hard sessions, a long-run jump,
    /// a high monotony.
    case dropSession(day: Date)
}
