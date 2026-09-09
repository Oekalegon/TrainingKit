import TrainingCore
import Foundation

extension ActivitySource {
    /// A stable string key for querying `ActivityRecord.sourceKey`.
    ///
    /// `ActivityStore.activity(source:)`/`deleteActivity(source:)` need to look up a record by its
    /// `ActivitySource`, but a SwiftData `#Predicate` can't inspect fields inside an opaque `Data`
    /// payload — so this key is stored as its own indexed column alongside the encoded payload.
    var persistenceKey: String {
        switch self {
        case .healthKit(let uuid):
            return "healthKit:\(uuid.uuidString)"
        case .fitFile(let url):
            // Two URLs can refer to the same file while differing in representation (trailing
            // slash, symlink, percent-encoding) — resolvingSymlinksInPath() is Foundation's own
            // recommended normalization for comparing file URLs, so two spellings of the same
            // file dedupe to the same key instead of silently producing two records for one import.
            return "fitFile:\(url.resolvingSymlinksInPath().absoluteString)"
        case .manual:
            return "manual"
        case .testing:
            return "testing"
        }
    }

    /// Persistence keys for sources with no natural key of their own (see `hasNaturalKey`), so
    /// code working with `ActivityRecord.sourceKey` strings can exclude them without decoding
    /// the payload back into an `ActivitySource`.
    static let keysWithoutNaturalKey: Set<String> = Set([ActivitySource.manual, .testing].map(\.persistenceKey))
}
