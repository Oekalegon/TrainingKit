import TrainingCore
import Foundation
import SwiftData

/// The joined-activity half of ``SwiftDataStore``'s `ActivityStore` conformance — split out to keep
/// `SwiftDataStore.swift` a manageable size. See ``ActivityJoinRecord`` for why the link lives in
/// its own table.
extension SwiftDataStore {
    /// See `ActivityStore/saveJoin(_:components:replacing:)`. One `modelContext.save()` covers the
    /// merged record, the link, and the replaced joins' removal, so it's all-or-nothing.
    public func saveJoin(_ merged: Activity, components: [UUID], replacing replacedJoinIDs: [UUID]) async throws {
        let ignored = Set(replacedJoinIDs).union([merged.id])
        let taken = Set(try joinComponentIDs().filter { !ignored.contains($0.key) }.values.joined())
        if let duplicate = components.first(where: taken.contains) {
            throw ActivityJoinError.componentAlreadyJoined(duplicate)
        }
        for id in replacedJoinIDs {
            try deleteJoinRecords(joinID: id)
            if let record = try fetchActivityRecord(id: id) { modelContext.delete(record) }
        }
        if let existing = try fetchActivityRecord(id: merged.id) {
            try existing.update(from: merged)
        } else {
            modelContext.insert(try ActivityRecord(activity: merged))
        }
        try deleteJoinRecords(joinID: merged.id)
        modelContext.insert(try ActivityJoinRecord(joinID: merged.id, componentIDs: components))
        try modelContext.save()
    }

    /// See `ActivityStore/joinedActivity(containing:)`.
    public func joinedActivity(containing componentID: UUID) async throws -> Activity? {
        guard let joinID = try joinComponentIDs().first(where: { $0.value.contains(componentID) })?.key else { return nil }
        return try fetchActivityRecord(id: joinID)?.toActivity()
    }

    /// See `ActivityStore/components(ofJoinedActivity:)`.
    public func components(ofJoinedActivity id: UUID) async throws -> [Activity] {
        let componentIDs = try joinComponentIDs()[id] ?? []
        return try componentIDs.compactMap { try fetchActivityRecord(id: $0)?.toActivity() }
            .sorted { $0.start < $1.start }
    }

    /// See `ActivityStore/unjoinActivity(id:)`.
    public func unjoinActivity(id: UUID) async throws {
        guard try joinComponentIDs()[id] != nil else { return }
        try deleteJoinRecords(joinID: id)
        if let record = try fetchActivityRecord(id: id) { modelContext.delete(record) }
        try modelContext.save()
    }

    /// Join id → component ids, for every stored join.
    func joinComponentIDs() throws -> [UUID: [UUID]] {
        var result: [UUID: [UUID]] = [:]
        for record in try modelContext.fetch(FetchDescriptor<ActivityJoinRecord>()) {
            result[record.joinID] = try record.componentIDs()
        }
        return result
    }

    func deleteJoinRecords(joinID: UUID) throws {
        let descriptor = FetchDescriptor<ActivityJoinRecord>(predicate: #Predicate { $0.joinID == joinID })
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
    }
}
