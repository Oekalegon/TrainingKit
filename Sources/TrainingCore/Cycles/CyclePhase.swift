import Foundation

/// The named training emphasis of a ``TrainingCycle``, such as `base`, `build` or `taper`.
///
/// A phase is an open, string-backed value rather than a fixed enum so a training paradigm can
/// define its own phases (e.g. a triphasic plan's `CyclePhase("structural")`) without a library
/// change. The built-in constants below keep the familiar names; they carry no behaviour of their
/// own. How hard a micro-cycle is meant to be — build, recovery, taper or race — is a separate
/// concern, recorded per micro as ``MicroLoadRole``.
///
/// Encodes as a plain string (its ``id``). Payloads written before phases became named values
/// stored the old enum, e.g. `{"build":{}}`; those decode to the matching constant.
public struct CyclePhase: Sendable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The phase's stable identifier, e.g. `"build"`. This is what is persisted.
    public let id: String

    /// Creates a phase with the given identifier.
    ///
    /// - Parameter id: The stable identifier; two phases with the same `id` are equal.
    public init(_ id: String) {
        self.id = id
    }

    /// Creates a phase from a string literal, so `let phase: CyclePhase = "structural"` works.
    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { id }

    /// General aerobic base building.
    public static let base = CyclePhase("base")
    /// Progressive loading towards race-specific fitness.
    public static let build = CyclePhase("build")
    /// The highest-load, most race-specific stretch before the taper.
    public static let peak = CyclePhase("peak")
    /// Reduced load ahead of a race.
    public static let taper = CyclePhase("taper")
    /// The race itself.
    public static let race = CyclePhase("race")
    /// A recovery phase.
    public static let recovery = CyclePhase("recovery")
    /// Off-season or post-race transition.
    public static let transition = CyclePhase("transition")

    /// Decodes a phase from its string form, or from the legacy enum form (`{"build":{}}`).
    public init(from decoder: Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(String.self) {
            self.init(id)
            return
        }
        // Synthesised `Codable` for the old enum encoded each case as a one-key object.
        let container = try decoder.container(keyedBy: LegacyKey.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a phase string or a single-case legacy phase object")
            )
        }
        self.init(key.stringValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    private struct LegacyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
