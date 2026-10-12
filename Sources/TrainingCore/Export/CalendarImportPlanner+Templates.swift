import Foundation

/// Decides which library template each file template is, as the planner reads the file (MVP2-141).
struct TemplateResolver {
    /// A file template's fate: an equal or same-id template the library has, or one to add.
    private enum Resolution {
        case existing(WorkoutTemplate)
        case new(WorkoutTemplate, isCopy: Bool)
    }

    /// A workout built from a template, and the file id of the template to commit once the workout's
    /// plan is added.
    struct Built {
        let workout: StructuredWorkout
        let templateFileID: UUID
    }

    private var library: [WorkoutTemplate]
    private var libraryByID: [UUID: WorkoutTemplate]
    private var resolutions: [UUID: Resolution] = [:]
    private var committed: Set<UUID> = []
    /// Templates to add, in the order they were first used.
    private(set) var added: [WorkoutTemplate] = []
    private(set) var addedCount = 0
    private(set) var linkedCount = 0
    private(set) var copiedCount = 0
    private(set) var rejectedCount = 0

    init(fileTemplates: [CalendarExport.Template], library: [WorkoutTemplate], canAdd: Bool) {
        self.library = library
        libraryByID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for fileTemplate in fileTemplates {
            guard let fileID = UUID(uuidString: fileTemplate.id), var template = fileTemplate.workoutTemplate() else {
                rejectedCount += 1
                continue
            }
            // Equal in what it does, whatever it's called; a live one in preference to an archived one.
            let equal = self.library.first { !$0.isArchived && Self.isEqual($0, template) }
                ?? self.library.first { Self.isEqual($0, template) }
            if let equal {
                resolutions[fileID] = .existing(equal)
                continue
            }
            guard canAdd else {
                rejectedCount += 1
                continue
            }
            let isCopy = libraryByID[template.id] != nil
            if isCopy {
                template = WorkoutTemplate(
                    name: template.name, titleName: template.titleName, sport: template.sport, venue: template.venue,
                    parameters: template.parameters, blocks: template.blocks
                )
            }
            resolutions[fileID] = .new(template, isCopy: isCopy)
            // Later file templates may equal this one.
            self.library.append(template)
        }
    }

    /// The workout `entry` describes, built from its template, or `nil` when it has none the library
    /// or the file provides.
    func workout(for entry: CalendarExport.Entry) -> Built? {
        guard let fileID = entry.templateID.flatMap(UUID.init(uuidString:)) else { return nil }
        let template: WorkoutTemplate
        switch resolutions[fileID] {
        case .existing(let existing): template = existing
        case .new(let new, _): template = new
        case nil:
            // Not defined in the file: a built-in template, or one the library already has by id.
            guard let known = libraryByID[fileID] else { return nil }
            template = known
        }
        // The file isn't trusted: a value the template doesn't declare, isn't a number, or is outside
        // the parameter's range is dropped, so the parameter keeps its default. A workout that still
        // makes no sense (a huge repeat count from a parameter with no range) isn't used.
        var values: [String: Double] = [:]
        for parameter in template.parameters {
            guard let value = entry.parameterValues?[parameter.key], value.isFinite,
                  parameter.range?.contains(value) ?? true
            else { continue }
            values[parameter.key] = value
        }
        guard let workout = try? template.instantiate(
            name: entry.name, venue: CalendarExportBuilder.venue(identifier: entry.sport, explicit: entry.venue), values: values
        ),
              CalendarExport.Template.isSane(workout)
        else { return nil }
        return Built(workout: workout, templateFileID: fileID)
    }

    /// Counts the template as used by an added plan, and queues it for adding if it is new.
    mutating func commit(_ fileID: UUID) {
        guard committed.insert(fileID).inserted, let resolution = resolutions[fileID] else { return }
        switch resolution {
        case .existing:
            linkedCount += 1
        case .new(let template, let isCopy):
            added.append(template)
            if isCopy { copiedCount += 1 } else { addedCount += 1 }
        }
    }

    /// Whether two templates do the same thing: the id, name and archived state don't count.
    private static func isEqual(_ lhs: WorkoutTemplate, _ rhs: WorkoutTemplate) -> Bool {
        lhs.sport == rhs.sport && lhs.venue == rhs.venue && lhs.parameters == rhs.parameters && lhs.blocks == rhs.blocks
    }
}
