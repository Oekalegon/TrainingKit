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

        /// Creates a meso block.
        ///
        /// - Parameters:
        ///   - phase: This meso's training emphasis.
        ///   - microCount: How many micro-cycles this meso spans.
        public init(phase: CyclePhase, microCount: Int) {
            self.phase = phase
            self.microCount = microCount
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
