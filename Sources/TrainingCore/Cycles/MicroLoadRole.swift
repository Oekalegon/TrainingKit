import Foundation

/// How hard a micro-cycle is meant to be within its mesocycle, independent of its
/// ``CyclePhase``.
///
/// The phase says what the athlete is working on (a paradigm-defined name); the role says how much
/// load the micro carries. Rules such as build progression read the role, so they keep working
/// whatever phases a paradigm defines.
public enum MicroLoadRole: String, Sendable, Codable, Hashable, CaseIterable {
    /// A loading micro; load is meant to progress from one build micro to the next.
    case build
    /// A reduced-load micro that absorbs the preceding build micros.
    case recovery
    /// A micro in the taper into a race.
    case taper
    /// The micro containing race day.
    case race
}
