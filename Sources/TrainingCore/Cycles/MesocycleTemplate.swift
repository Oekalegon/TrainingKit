import Foundation

/// A repeating build/recovery pattern applied within a mesocycle, so ``CycleLayoutBuilder``
/// doesn't need every week laid out by hand.
///
/// `microRoles` cycles across the micros of any ``MacroTemplate/MesoBlock`` that isn't `.taper`
/// or `.race` — e.g. the classic "3:1" pattern (`[.build, .build, .build, .recovery]`) applied to
/// an 8-micro base block produces `build, build, build, recovery, build, build, build, recovery`
/// load roles; each micro keeps its block's ``CyclePhase``.
/// Taper and race blocks are handled specially by the builder instead of cycling this pattern; see
/// ``CycleLayoutBuilder``.
public struct MesocycleTemplate: Sendable, Codable, Hashable {
    /// The template's display name, e.g. `"3:1"`.
    public var name: String
    /// The repeating load-role pattern applied across a block's micros, e.g. `[.build, .build, .build, .recovery]`.
    public var microRoles: [MicroLoadRole]
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
    ///   - microRoles: The repeating load-role pattern applied across a block's micros.
    ///   - microLengthDays: The length of each micro-cycle, in days; defaults to 7.
    ///   - recoveryLoadFraction: A recovery micro's target load relative to the prior micro's peak;
    ///     defaults to 0.6.
    ///   - buildLoadStep: The fractional load increase from one build micro to the next; defaults
    ///     to 0.08.
    public init(
        name: String,
        microRoles: [MicroLoadRole],
        microLengthDays: Int = 7,
        recoveryLoadFraction: Double = 0.6,
        buildLoadStep: Double = 0.08
    ) {
        self.name = name
        self.microRoles = microRoles
        self.microLengthDays = microLengthDays
        self.recoveryLoadFraction = recoveryLoadFraction
        self.buildLoadStep = buildLoadStep
    }

    /// Three build micros followed by one recovery micro.
    public static let threeToOne = MesocycleTemplate(name: "3:1", microRoles: [.build, .build, .build, .recovery])
    /// Two build micros followed by one recovery micro.
    public static let twoToOne = MesocycleTemplate(name: "2:1", microRoles: [.build, .build, .recovery])
    /// Every micro is a build micro; no recovery week, for short blocks.
    public static let linear = MesocycleTemplate(name: "linear", microRoles: [.build])
}

extension MesocycleTemplate {
    private enum CodingKeys: String, CodingKey {
        case name, microRoles, microPhases, microLengthDays, recoveryLoadFraction, buildLoadStep
    }

    /// Decodes a template, including payloads written when the pattern was stored as
    /// `microPhases`; each legacy phase maps to the load role of the same name (any other phase
    /// counts as `build`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if let roles = try container.decodeIfPresent([MicroLoadRole].self, forKey: .microRoles) {
            microRoles = roles
        } else {
            let legacy = try container.decode([CyclePhase].self, forKey: .microPhases)
            microRoles = legacy.map { MicroLoadRole(rawValue: $0.id) ?? .build }
        }
        microLengthDays = try container.decode(Int.self, forKey: .microLengthDays)
        recoveryLoadFraction = try container.decode(Double.self, forKey: .recoveryLoadFraction)
        buildLoadStep = try container.decode(Double.self, forKey: .buildLoadStep)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(microRoles, forKey: .microRoles)
        try container.encode(microLengthDays, forKey: .microLengthDays)
        try container.encode(recoveryLoadFraction, forKey: .recoveryLoadFraction)
        try container.encode(buildLoadStep, forKey: .buildLoadStep)
    }
}
