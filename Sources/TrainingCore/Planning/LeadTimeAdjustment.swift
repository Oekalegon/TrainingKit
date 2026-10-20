import Foundation

/// The macro after ``LeadTimeCompromiser`` fitted it into the lead time, with what was given up.
public struct LeadTimeAdjustment: Sendable, Codable, Hashable {
    /// The macro to lay out, at most as long as the lead time. Pass it to ``CycleLayoutBuilder``.
    public var macro: MacroTemplate
    /// The changes made, in the order they were made; empty when the macro already fitted.
    public var compromises: [LeadTimeCompromise]

    /// Creates an adjustment.
    ///
    /// - Parameters:
    ///   - macro: The macro to lay out.
    ///   - compromises: The changes made to it.
    public init(macro: MacroTemplate, compromises: [LeadTimeCompromise]) {
        self.macro = macro
        self.compromises = compromises
    }
}
