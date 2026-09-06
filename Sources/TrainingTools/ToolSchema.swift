import Foundation

/// A ``TrainingTool``'s name, description, and input ``JSONSchema``, as rendered by an adapter
/// (`TrainingToolsAnthropic`, `TrainingToolsFoundationModels`) into its provider's tool format.
public struct ToolSchema: Sendable, Equatable {
    /// The name a model calls this tool by.
    public let name: String
    /// What this tool does, written for the model.
    public let description: String
    /// Whether this tool writes to the sandbox rather than only reading.
    public let isMutating: Bool
    /// The tool's `Input` shape, for an adapter to render into its provider's tool format.
    public let inputSchema: JSONSchema

    public init(name: String, description: String, isMutating: Bool, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.isMutating = isMutating
        self.inputSchema = inputSchema
    }
}
