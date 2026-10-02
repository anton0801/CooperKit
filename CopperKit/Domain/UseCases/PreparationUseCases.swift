import Foundation

/// The state of one preparation line against the stock as it is right now.
enum PrepLineState: Equatable {
    case removed
    /// Something changed under the line — fix it before checkout.
    case needsReview(String)
    /// More is required than is Available.
    case short(missing: Int)
    case notPrepared
    case ready

    var blocksCheckout: Bool {
        switch self {
        case .needsReview, .short: return true
        case .removed, .notPrepared, .ready: return false
        }
    }
}

struct PrepLineEvaluation: Identifiable, Equatable {
    var line: PreparationLine
    var tool: Tool?
    var availableNow: Int
    var state: PrepLineState

    var id: UUID { line.id }
}

struct PrepEvaluation: Equatable {
    var lines: [PrepLineEvaluation]

    var activeLines: [PrepLineEvaluation] { lines.filter { $0.state != .removed } }
    var preparedCount: Int { activeLines.filter { $0.state == .ready }.count }
    var blockingCount: Int { activeLines.filter { $0.state.blocksCheckout }.count }
    var canCheckout: Bool { !activeLines.isEmpty && blockingCount == 0 }

    var blockingReason: String? {
        if activeLines.isEmpty { return "The kit is empty for this run. Add or restore at least one tool." }
        if blockingCount > 0 {
            return blockingCount == 1
                ? "1 line needs attention: replace the tool, reduce the quantity or remove it for this run."
                : "\(blockingCount) lines need attention: replace the tool, reduce the quantity or remove them for this run."
        }
        return nil
    }
}

enum PreparationRules {
    /// Preparation never reserves anything — this only compares the run with Available now.
    static func evaluate(_ run: PreparationRun, in workshop: Workshop, balances: [UUID: ToolBalance]) -> PrepEvaluation {
        PrepEvaluation(lines: run.lines.map { line in
            let tool = workshop.tool(line.toolID)
            let available = balances[line.toolID]?.available ?? 0
            let state: PrepLineState
            if line.isRemoved {
                state = .removed
            } else if tool == nil {
                state = .needsReview("Tool removed from the catalogue")
            } else if tool?.isArchived == true {
                state = .needsReview("Tool archived")
            } else if line.runQuantity > available {
                state = line.isPrepared
                    ? .needsReview(available == 0 ? "Marked prepared, but none are Available now" : "Marked prepared, but only \(available) Available now")
                    : .short(missing: line.runQuantity - available)
            } else {
                state = line.isPrepared ? .ready : .notPrepared
            }
            return PrepLineEvaluation(line: line, tool: tool, availableNow: available, state: state)
        })
    }

    static func summary(_ run: PreparationRun, evaluation: PrepEvaluation, kitName: String?) -> String {
        var parts: [String] = []
        if let kitName { parts.append("Kit: \(kitName)") }
        let active = evaluation.activeLines.count
        parts.append("\(evaluation.preparedCount) of \(active) \(active == 1 ? "line" : "lines") marked prepared")
        let replaced = run.activeLines.filter(\.isReplacement).count
        if replaced > 0 { parts.append("\(replaced) replaced for this run") }
        let reduced = run.activeLines.filter { $0.templateToolID != nil && $0.runQuantity < $0.requiredQuantity }.count
        if reduced > 0 { parts.append("\(reduced) reduced for this run") }
        let removed = run.lines.filter(\.isRemoved).count
        if removed > 0 { parts.append("\(removed) removed for this run") }
        if let note = run.runNote.nilIfBlank { parts.append("Run note: \(note)") }
        return parts.joined(separator: " · ")
    }
}

extension PreparationRun {
    mutating func setPrepared(_ lineID: UUID, _ prepared: Bool) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[index].isPrepared = prepared
    }

    mutating func setQuantity(_ lineID: UUID, _ quantity: Int) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[index].runQuantity = try Validate.quantity(quantity)
    }

    mutating func replace(_ lineID: UUID, with tool: Tool) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        if lines.contains(where: { $0.id != lineID && !$0.isRemoved && $0.toolID == tool.id }) {
            throw DomainError("\(tool.name) is already in this run. Change that line's quantity instead.")
        }
        guard !tool.isArchived else { throw DomainError("\(tool.name) is archived.") }
        lines[index].toolID = tool.id
        lines[index].toolNameSnapshot = tool.name
        lines[index].isPrepared = false
    }

    mutating func setRemoved(_ lineID: UUID, _ removed: Bool) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        if !removed, lines.contains(where: { $0.id != lineID && !$0.isRemoved && $0.toolID == lines[index].toolID }) {
            throw DomainError("This tool is already in the run on another line.")
        }
        lines[index].isRemoved = removed
        if removed { lines[index].isPrepared = false }
    }

    mutating func add(_ tool: Tool, quantity: Int) throws {
        if let index = lines.firstIndex(where: { !$0.isRemoved && $0.toolID == tool.id }) {
            throw DomainError("\(lines[index].toolNameSnapshot) is already in this run. Change its quantity instead.")
        }
        guard !tool.isArchived else { throw DomainError("\(tool.name) is archived.") }
        lines.append(PreparationLine(
            id: UUID(), templateToolID: nil, toolID: tool.id, toolNameSnapshot: tool.name,
            requiredQuantity: quantity, runQuantity: try Validate.quantity(quantity), isPrepared: false, isRemoved: false
        ))
    }
}

final class PreparationUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    /// The saved run for a kit, or a fresh one built from the template's needs.
    func run(forKit kitID: UUID) throws -> PreparationRun {
        let workshop = repository.workshop
        guard let kit = workshop.kit(kitID) else { throw DomainError.kitMissing }
        if let saved = workshop.preparations.first(where: { $0.kitID == kitID && $0.sourceHandoverID == nil }) {
            return saved
        }
        let now = clock.now
        return PreparationRun(
            id: UUID(), kitID: kit.id, title: kit.name, sourceHandoverID: nil,
            lines: kit.lines.map {
                PreparationLine(id: UUID(), templateToolID: $0.toolID, toolID: $0.toolID,
                                toolNameSnapshot: workshop.tool($0.toolID)?.name ?? $0.toolNameSnapshot,
                                requiredQuantity: $0.requiredQuantity, runQuantity: $0.requiredQuantity,
                                isPrepared: false, isRemoved: false)
            },
            runNote: "", createdAt: now, updatedAt: now
        )
    }

    /// Repeat: copies the list of needs from an earlier handover — not its dates, notes
    /// or return marks.
    func repeatRun(ofHandover handoverID: UUID) throws -> PreparationRun {
        let workshop = repository.workshop
        guard let handover = workshop.handover(handoverID) else { throw DomainError.handoverMissing }
        if let saved = workshop.preparations.first(where: { $0.sourceHandoverID == handoverID }) {
            return saved
        }
        let now = clock.now
        let kitID = handover.kitID.flatMap { workshop.kit($0)?.id }
        return PreparationRun(
            id: UUID(), kitID: kitID,
            title: handover.kitNameSnapshot.nilIfBlank ?? handover.purpose,
            sourceHandoverID: handover.id,
            lines: handover.lines.map {
                PreparationLine(id: UUID(), templateToolID: $0.toolID, toolID: $0.toolID,
                                toolNameSnapshot: workshop.tool($0.toolID)?.name ?? $0.toolNameSnapshot,
                                requiredQuantity: $0.quantity, runQuantity: $0.quantity,
                                isPrepared: false, isRemoved: false)
            },
            runNote: "", createdAt: now, updatedAt: now
        )
    }

    func save(_ run: PreparationRun) throws {
        _ = try Validate.text(run.runNote, max: Limits.notesMax, field: "Run Note")
        let now = clock.now
        try repository.transact { workshop in
            var run = run
            run.updatedAt = now
            if let index = workshop.preparations.firstIndex(where: { $0.id == run.id }) {
                workshop.preparations[index] = run
            } else {
                workshop.preparations.append(run)
            }
        }
    }

    func discard(_ runID: UUID) throws {
        try repository.transact { workshop in
            workshop.preparations.removeAll { $0.id == runID }
        }
    }

    /// Update Template: writes this run's tools and quantities back to the kit. Only on
    /// explicit request — replacements and reductions are otherwise for this run alone.
    func updateTemplate(from run: PreparationRun) throws {
        guard let kitID = run.kitID else { throw DomainError("This run is not linked to a kit template.") }
        let now = clock.now
        let active = run.activeLines
        guard Limits.kitLines.contains(active.count) else {
            throw DomainError(active.isEmpty ? "A template needs at least one tool." : "A kit can hold up to \(Limits.kitLines.upperBound) tools.")
        }
        try repository.transact { workshop in
            let index = try workshop.kitIndex(kitID)
            var seen = Set<UUID>()
            var lines: [KitLine] = []
            for line in active {
                guard seen.insert(line.toolID).inserted else { throw DomainError("Each tool can appear once in a kit.") }
                guard let tool = workshop.tool(line.toolID), !tool.isArchived else {
                    throw DomainError("\(line.toolNameSnapshot) needs review before it can be saved to the template.")
                }
                lines.append(KitLine(id: UUID(), toolID: tool.id, toolNameSnapshot: tool.name, requiredQuantity: line.runQuantity))
            }
            workshop.kits[index].lines = lines
            workshop.kits[index].updatedAt = now
            workshop.log(.kitSaved, at: now, title: "Updated kit \(workshop.kits[index].name) from a run",
                         detail: "\(lines.count) \(lines.count == 1 ? "tool" : "tools")", kit: kitID)
        }
    }
}
