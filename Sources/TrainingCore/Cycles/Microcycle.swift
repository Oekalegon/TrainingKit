import Foundation

/// One micro-cycle in a planned periodisation layout, before it's turned into a persisted
/// ``TrainingCycle``.
///
/// ``CycleLayoutBuilder/microcycles(from:to:macro:meso:athlete:)`` returns these so a caller can
/// inspect — or let the user tweak — the planned week-by-week phase progression before committing
/// it to ``TrainingCycle``/``CycleStore`` via ``CycleLayoutBuilder/layout(from:to:macro:meso:athlete:)``.
public struct Microcycle: Identifiable, Sendable, Codable, Hashable {
    /// The start of `dateRange`, used as a stable id within one layout (no two micro-cycles in the
    /// same layout share a start day).
    public var id: Date { dateRange.lowerBound }
    /// Day-granular date range, in the athlete's timezone.
    public let dateRange: ClosedRange<Date>
    /// This micro-cycle's training emphasis.
    public let phase: CyclePhase
    /// How hard this micro-cycle is meant to be within its mesocycle.
    public let loadRole: MicroLoadRole
    /// The index into the originating ``MacroTemplate/mesoBlocks`` this micro-cycle belongs to.
    public let mesoBlockIndex: Int

    /// Creates a micro-cycle.
    ///
    /// - Parameters:
    ///   - dateRange: Day-granular date range, in the athlete's timezone.
    ///   - phase: This micro-cycle's training emphasis.
    ///   - loadRole: How hard this micro-cycle is meant to be within its mesocycle.
    ///   - mesoBlockIndex: The index into the originating ``MacroTemplate/mesoBlocks`` this
    ///     micro-cycle belongs to.
    public init(dateRange: ClosedRange<Date>, phase: CyclePhase, loadRole: MicroLoadRole, mesoBlockIndex: Int) {
        self.dateRange = dateRange
        self.phase = phase
        self.loadRole = loadRole
        self.mesoBlockIndex = mesoBlockIndex
    }

    private enum CodingKeys: String, CodingKey {
        case dateRange, phase, loadRole, mesoBlockIndex
    }

    /// Decodes a micro-cycle, including payloads written before load roles existed; those get the
    /// role ``MicroLoadRole/init(legacyPhase:)`` derives from the stored phase.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateRange = try container.decode(ClosedRange<Date>.self, forKey: .dateRange)
        phase = try container.decode(CyclePhase.self, forKey: .phase)
        loadRole = try container.decodeIfPresent(MicroLoadRole.self, forKey: .loadRole) ?? MicroLoadRole(legacyPhase: phase)
        mesoBlockIndex = try container.decode(Int.self, forKey: .mesoBlockIndex)
    }
}
