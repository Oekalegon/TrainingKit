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
            return "fitFile:\(url.absoluteString)"
        case .manual:
            return "manual"
        }
    }
}
