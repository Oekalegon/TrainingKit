import TrainingTools

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Maps the tool registry onto Apple's on-device `FoundationModels` `Tool` protocol and
/// `@Generable` types. iOS 26+/macOS 26+ only.
public enum TrainingToolsFoundationModels {}
