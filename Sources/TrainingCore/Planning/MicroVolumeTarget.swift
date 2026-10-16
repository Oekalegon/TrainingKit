import Foundation

/// The volume planned for one micro-cycle, from ``VolumeCurveBuilder``.
public struct MicroVolumeTarget: Identifiable, Sendable, Hashable {
    /// The start of the micro, like ``Microcycle/id``.
    public var id: Date { microStart }
    /// The first day of the micro.
    public let microStart: Date
    /// The micro's length in days.
    public let lengthDays: Int
    /// The micro's phase.
    public let phase: CyclePhase
    /// The micro's load role.
    public let loadRole: MicroLoadRole
    /// The volume for the whole micro, in the measure of the curve's inputs. The volume per 7 days
    /// is the amount divided by `lengthDays / 7`.
    public let target: VolumeTarget

    /// Creates a micro volume target.
    ///
    /// - Parameters:
    ///   - microStart: The first day of the micro.
    ///   - lengthDays: The micro's length in days.
    ///   - phase: The micro's phase.
    ///   - loadRole: The micro's load role.
    ///   - target: The volume for the whole micro.
    public init(microStart: Date, lengthDays: Int, phase: CyclePhase, loadRole: MicroLoadRole, target: VolumeTarget) {
        self.microStart = microStart
        self.lengthDays = lengthDays
        self.phase = phase
        self.loadRole = loadRole
        self.target = target
    }
}
