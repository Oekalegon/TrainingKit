import Foundation
import TrainingCore

/// A provider-neutral tool an LLM coach can call.
///
/// The model never computes fitness numbers itself — every tool wraps a `TrainingCore`
/// computation or store read/write, and every mutation lands in ``ToolContext/sandbox`` rather
/// than the committed stores. `Input`/`Output` are plain `Codable` value types so a tool can be
/// dispatched by name from JSON arguments (see ``ToolRegistry``) without either adapter knowing
/// the concrete tool type.
public protocol TrainingTool: Sendable {
    associatedtype Input: ToolInput
    associatedtype Output: Codable & Sendable

    /// The name the model calls this tool by, e.g. `"list_activities"`.
    static var name: String { get }
    /// What this tool does, written for the model rather than for documentation.
    static var description: String { get }
    /// Whether this tool writes to ``ToolContext/sandbox``. Mirrored into ``ToolSchema`` so an
    /// adapter can label mutating tools distinctly, and checked by ``ToolRegistry`` policies
    /// that only want to expose read-only tools.
    static var isMutating: Bool { get }

    func run(_ input: Input, context: ToolContext) async throws -> Output
}

/// Everything a ``TrainingTool`` needs to run: the committed stores, the sandbox mutations land
/// in, and the athlete/date context that makes a run reproducible.
public struct ToolContext: Sendable {
    /// The committed stores read-only tools read from.
    public let stores: StoreSet
    /// Where every mutating tool's changes land instead of `stores`.
    public let sandbox: PlanSandbox
    /// The boundary between actual and projected days, injected rather than `Date()` so a tool
    /// run — and a whole replayed conversation — stays deterministic and testable.
    public let today: Date
    /// The athlete a tool call is running for.
    public let athlete: AthleteProfile

    public init(stores: StoreSet, sandbox: PlanSandbox, today: Date, athlete: AthleteProfile) {
        self.stores = stores
        self.sandbox = sandbox
        self.today = today
        self.athlete = athlete
    }
}
