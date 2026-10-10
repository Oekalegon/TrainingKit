import Foundation

extension CalendarExport {
    /// The full definition of a custom workout template a planned entry was built from (MVP2-141),
    /// so an import can add the template to the library and link the imported workouts to it.
    ///
    /// Written in the file's own vocabulary (kinds, goals and units as strings, like ``Step``), not
    /// as ``WorkoutTemplate``'s encoding, so the format doesn't change when the model does. Fields
    /// that don't apply are left out of the JSON.
    public struct Template: Sendable, Codable, Hashable {
        /// The template's id; the planned entries' ``Entry/templateID`` refers to it.
        public let id: String
        /// The template's name.
        public let name: String
        /// A shorter name for generated titles, if the template has one.
        public let titleName: String?
        /// The sport, with the same identifiers as ``Entry/sport``.
        public let sport: String
        /// The parameters the blocks may refer to.
        public let parameters: [Parameter]
        /// The template's blocks, in order.
        public let blocks: [Block]

        /// A value the athlete can choose when planning.
        public struct Parameter: Sendable, Codable, Hashable {
            /// The key blocks and steps refer to.
            public let key: String
            /// The name shown to the athlete.
            public let name: String
            /// `minutes`, `meters` or `count`.
            public let unit: String
            /// The value used when none is chosen.
            public let defaultValue: Double
            /// The lowest value the athlete can choose, with ``max``; both are absent for no range.
            public let min: Double?
            /// The highest value the athlete can choose.
            public let max: Double?
        }

        /// Steps that repeat together.
        public struct Block: Sendable, Codable, Hashable {
            /// A fixed repeat count; absent when ``repetitionsParameter`` sets it.
            public let repetitions: Int?
            /// The key of the parameter that sets the repeat count.
            public let repetitionsParameter: String?
            /// One repetition's steps.
            public let steps: [Step]
        }

        /// One step of a block.
        public struct Step: Sendable, Codable, Hashable {
            /// `warmup`, `work`, `recovery` or `cooldown`.
            public let kind: String
            /// What ends the step: `time`, `distance` or `open`.
            public let goal: String
            /// A fixed duration in seconds, for a `time` goal.
            public let durationSeconds: Double?
            /// The key of the parameter that sets the duration.
            public let durationParameter: String?
            /// A fixed distance in meters, for a `distance` goal.
            public let distanceMeters: Double?
            /// The key of the parameter that sets the distance.
            public let distanceParameter: String?
            /// The intensity the step targets, if any.
            public let target: Target?
        }
    }
}

extension CalendarExport.Template {
    /// The file's form of `template`.
    init(_ template: WorkoutTemplate) {
        self.init(
            id: template.id.uuidString,
            name: template.name,
            titleName: template.titleName,
            sport: CalendarExportBuilder.sportIdentifier(template.sport),
            parameters: template.parameters.map { parameter in
                Parameter(
                    key: parameter.key, name: parameter.name, unit: Self.unitIdentifier(parameter.unit),
                    defaultValue: parameter.defaultValue,
                    min: parameter.range?.lowerBound, max: parameter.range?.upperBound
                )
            },
            blocks: template.blocks.map { block in
                var repetitions: Int?
                var repetitionsParameter: String?
                switch block.repetitions {
                case .fixed(let count): repetitions = count
                case .parameter(let key): repetitionsParameter = key
                }
                return Block(repetitions: repetitions, repetitionsParameter: repetitionsParameter, steps: block.steps.map(Self.step))
            }
        )
    }

    /// The template this describes, or `nil` when it can't be read: an id that isn't a UUID, an
    /// unknown kind, goal or unit, a goal without its value, a block without a repeat count, a range
    /// that is backwards, or a parameter the blocks refer to but the template doesn't declare.
    func workoutTemplate() -> WorkoutTemplate? {
        guard let templateID = UUID(uuidString: id) else { return nil }
        var parameters: [WorkoutTemplateParameter] = []
        for parameter in self.parameters {
            guard let unit = Self.unit(identifier: parameter.unit), parameter.defaultValue.isFinite else { return nil }
            var range: ClosedRange<Double>?
            switch (parameter.min, parameter.max) {
            case (let low?, let high?):
                guard low.isFinite, high.isFinite, low <= high else { return nil }
                range = low...high
            case (nil, nil):
                break
            default:
                return nil
            }
            parameters.append(WorkoutTemplateParameter(
                key: parameter.key, name: parameter.name, unit: unit, defaultValue: parameter.defaultValue, range: range
            ))
        }
        var blocks: [TemplateBlock] = []
        for block in self.blocks {
            let repetitions: TemplateValue<Int>
            switch (block.repetitions, block.repetitionsParameter) {
            case (let count?, nil): repetitions = .fixed(count)
            case (nil, let key?): repetitions = .parameter(key)
            default: return nil
            }
            var steps: [TemplateStep] = []
            for step in block.steps {
                guard let converted = Self.templateStep(step) else { return nil }
                steps.append(converted)
            }
            blocks.append(TemplateBlock(steps: steps, repetitions: repetitions))
        }
        let template = WorkoutTemplate(
            id: templateID, name: name, titleName: titleName, sport: CalendarExportBuilder.sport(identifier: sport),
            parameters: parameters, blocks: blocks
        )
        // Resolves every reference, so one to an undeclared parameter is caught here.
        guard (try? template.instantiate()) != nil else { return nil }
        return template
    }

    private static func step(_ step: TemplateStep) -> Step {
        var goal = "open"
        var durationSeconds: Double?
        var durationParameter: String?
        var distanceMeters: Double?
        var distanceParameter: String?
        switch step.goal {
        case .time(.fixed(let seconds)): (goal, durationSeconds) = ("time", seconds)
        case .time(.parameter(let key)): (goal, durationParameter) = ("time", key)
        case .distance(.fixed(let meters)): (goal, distanceMeters) = ("distance", meters)
        case .distance(.parameter(let key)): (goal, distanceParameter) = ("distance", key)
        case .open: break
        }
        return Step(
            kind: CalendarExportBuilder.stepKindIdentifier(step.kind), goal: goal,
            durationSeconds: durationSeconds, durationParameter: durationParameter,
            distanceMeters: distanceMeters, distanceParameter: distanceParameter,
            target: step.target.map(CalendarExportBuilder.target)
        )
    }

    private static func templateStep(_ step: Step) -> TemplateStep? {
        guard let kind = CalendarImportPlanner.stepKind(identifier: step.kind) else { return nil }
        let goal: TemplateStepGoal
        switch (step.goal, step.durationSeconds, step.durationParameter, step.distanceMeters, step.distanceParameter) {
        case ("time", let seconds?, nil, _, _): goal = .time(.fixed(seconds))
        case ("time", nil, let key?, _, _): goal = .time(.parameter(key))
        case ("distance", _, _, let meters?, nil): goal = .distance(.fixed(meters))
        case ("distance", _, _, nil, let key?): goal = .distance(.parameter(key))
        case ("open", _, _, _, _): goal = .open
        default: return nil
        }
        let target = step.target.flatMap(CalendarImportPlanner.target(from:))
        // A target that is present but unreadable would silently turn a step into an untargeted one.
        if step.target != nil, target == nil { return nil }
        return TemplateStep(kind: kind, goal: goal, target: target)
    }

    private static func unitIdentifier(_ unit: ParameterUnit) -> String {
        switch unit {
        case .minutes: "minutes"
        case .meters: "meters"
        case .count: "count"
        }
    }

    private static func unit(identifier: String) -> ParameterUnit? {
        switch identifier {
        case "minutes": .minutes
        case "meters": .meters
        case "count": .count
        default: nil
        }
    }
}
