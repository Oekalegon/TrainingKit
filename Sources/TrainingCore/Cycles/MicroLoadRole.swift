import Foundation

/// How hard a micro-cycle is meant to be within its mesocycle, independent of its
/// ``CyclePhase``.
///
/// The phase says what the athlete is working on (a paradigm-defined name); the role says how much
/// load the micro carries. Rules that care how hard a micro is read the role, so they keep working
/// whatever phases a paradigm defines.
public enum MicroLoadRole: String, Sendable, Codable, Hashable, CaseIterable {
    /// A loading micro; load is meant to progress from one build micro to the next.
    case build
    /// A reduced-load micro that absorbs the preceding build micros.
    case recovery
    /// A micro in the taper into a race.
    case taper
    /// The micro containing race day.
    ///
    /// ``CycleLayoutBuilder`` and ``KeyRaceLayout`` no longer produce it: the micro with race day
    /// is `.taper`, or `.recovery` when race day is its first day. It stays so stored micros decode.
    case race

    /// The role a micro stored before load roles existed had, judged from its phase: `build`,
    /// `recovery`, `taper` and `race` map to the role of the same name, any other phase to `build`.
    ///
    /// - Parameter phase: The stored phase.
    public init(legacyPhase phase: CyclePhase) {
        self = MicroLoadRole(rawValue: phase.id) ?? .build
    }
}
