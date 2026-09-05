import Foundation

/// A repeating build/recovery pattern applied within a mesocycle, so ``CycleLayoutBuilder``
/// doesn't need every week laid out by hand.
///
/// `microPhases` cycles across the micros of any ``MacroTemplate/MesoBlock`` that isn't `.taper`
/// or `.race` — e.g. the classic "3:1" pattern (`[.build, .build, .build, .recovery]`) applied to
/// an 8-micro base block produces `build, build, build, recovery, build, build, build, recovery`.
/// Taper and race blocks are handled specially by the builder instead of cycling this pattern; see
/// ``CycleLayoutBuilder``.
public struct MesocycleTemplate: Sendable, Codable, Hashable {
    /// The template's display name, e.g. `"3:1"`.
    public var name: String
    /// The repeating phase pattern applied across a block's micros, e.g. `[.build, .build, .build, .recovery]`.
    public var microPhases: [CyclePhase]
    /// The length of each micro-cycle, in days.
    public var microLengthDays: Int
    /// A recovery micro's target load relative to the prior micro's peak, as a fraction.
    public var recoveryLoadFraction: Double
    /// The fractional load increase from one build micro to the next.
    public var buildLoadStep: Double

    /// Creates a mesocycle template.
    ///
    /// - Parameters:
    ///   - name: The template's display name.
    ///   - microPhases: The repeating phase pattern applied across a block's micros.
    ///   - microLengthDays: The length of each micro-cycle, in days; defaults to 7.
    ///   - recoveryLoadFraction: A recovery micro's target load relative to the prior micro's peak;
    ///     defaults to 0.6.
    ///   - buildLoadStep: The fractional load increase from one build micro to the next; defaults
    ///     to 0.08.
    public init(
        name: String,
        microPhases: [CyclePhase],
        microLengthDays: Int = 7,
        recoveryLoadFraction: Double = 0.6,
        buildLoadStep: Double = 0.08
    ) {
        self.name = name
        self.microPhases = microPhases
        self.microLengthDays = microLengthDays
        self.recoveryLoadFraction = recoveryLoadFraction
        self.buildLoadStep = buildLoadStep
    }

    /// Three build micros followed by one recovery micro.
    public static let threeToOne = MesocycleTemplate(name: "3:1", microPhases: [.build, .build, .build, .recovery])
    /// Two build micros followed by one recovery micro.
    public static let twoToOne = MesocycleTemplate(name: "2:1", microPhases: [.build, .build, .recovery])
    /// Every micro is a build micro; no recovery week, for short blocks.
    public static let linear = MesocycleTemplate(name: "linear", microPhases: [.build])
}
