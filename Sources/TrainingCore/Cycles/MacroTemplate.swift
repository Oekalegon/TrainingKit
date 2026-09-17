import Foundation

/// The ordered phase structure of a macrocycle, e.g. `[.base, .base, .build, .build, .peak, .taper]`.
///
/// Each ``MesoBlock`` becomes one meso-level ``TrainingCycle`` in ``CycleLayoutBuilder``'s output;
/// listing the same phase twice in a row (as in the example above) produces two separate
/// meso-level cycles of that phase rather than one combined one, matching how a coach would
/// actually name and track them ("Meso 1", "Meso 2").
public struct MacroTemplate: Sendable, Codable, Hashable {
    /// One mesocycle's phase and length within a ``MacroTemplate``.
    public struct MesoBlock: Sendable, Codable, Hashable {
        /// This meso's training emphasis.
        public var phase: CyclePhase
        /// How many micro-cycles this meso spans.
        public var microCount: Int
        /// The build/recovery pattern for this block's micros, overriding the `meso` parameter
        /// passed to ``CycleLayoutBuilder``. `nil` (the default) uses that parameter as-is — set
        /// this only for a block that needs a different pattern than the rest of the macro, e.g. a
        /// base phase on "2:1" inside a macro whose build phase uses "3:1".
        public var pattern: MesocycleTemplate?

        /// Creates a meso block.
        ///
        /// - Parameters:
        ///   - phase: This meso's training emphasis.
        ///   - microCount: How many micro-cycles this meso spans.
        ///   - pattern: The build/recovery pattern for this block's micros, overriding
        ///     ``CycleLayoutBuilder``'s `meso` parameter; defaults to `nil` (use that parameter).
        public init(phase: CyclePhase, microCount: Int, pattern: MesocycleTemplate? = nil) {
            self.phase = phase
            self.microCount = microCount
            self.pattern = pattern
        }
    }

    /// The template's display name, e.g. `"Marathon build"`.
    public var name: String
    /// The mesocycles making up this macrocycle, in chronological order.
    public var mesoBlocks: [MesoBlock]

    /// Creates a macro template.
    ///
    /// - Parameters:
    ///   - name: The template's display name.
    ///   - mesoBlocks: The mesocycles making up this macrocycle, in chronological order.
    public init(name: String, mesoBlocks: [MesoBlock]) {
        self.name = name
        self.mesoBlocks = mesoBlocks
    }
}
