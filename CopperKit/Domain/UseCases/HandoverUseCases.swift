import Foundation

struct CheckoutRequest: Equatable {
    struct Line: Identifiable, Equatable {
        var id: UUID = UUID()
        var toolID: UUID
        var quantity: Int
    }

    /// Generated once per review screen. A second tap with the same key returns the
    /// handover already created instead of handing out a second kit.
    var operationID: UUID
    var mode: HandoverMode
    var purpose: String
    var recipientName: String
    var contactNote: String
    var startedAt: Date
    var dueAt: Date
    var dueTimeZoneID: String
    var lines: [Line]
    var conditionOutNote: String
    var preparationSummary: String
    var kitID: UUID?
    /// The saved preparation this checkout consumes, removed on success.
    var preparationRunID: UUID?
}

struct ReturnRequest: Equatable {
    struct Line: Equatable {
        var lineID: UUID
        var toAvailable: Int = 0
        var needsService: Int = 0
        var lost: Int = 0
        var issueNote: String = ""

        var total: Int { toAvailable + needsService + lost }
    }

    var operationID: UUID
    var handoverID: UUID
    var returnedAt: Date
    var note: String
    var lines: [Line]
}

final class HandoverUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    // MARK: - Checkout

    /// Confirm Checkout: moves every line from Available to In Use or On Loan in one
    /// transaction. Availability is checked again here, not trusted from the screen.
    @discardableResult
    func checkout(_ request: CheckoutRequest) throws -> Handover {
        let now = clock.now
        if let existing = repository.workshop.handovers.first(where: { $0.operationID == request.operationID }) {
            return existing
        }

        let purpose = try Validate.required(request.purpose, max: Limits.checkoutPurpose.upperBound, field: "Purpose")
        let recipient: String
        switch request.mode {
        case .loan:
            recipient = try Validate.required(request.recipientName, max: Limits.recipientMax, field: "Recipient Name")
        case .personalUse:
            recipient = ""
        }
        let contact = try Validate.text(request.mode == .loan ? request.contactNote : "", max: Limits.contactNoteMax, field: "Contact Note")
        let condition = try Validate.text(request.conditionOutNote, max: Limits.conditionNoteMax, field: "Condition Out Note")
        guard request.startedAt <= now else { throw DomainError("Started At cannot be in the future.") }
        guard request.dueAt >= request.startedAt else { throw DomainError("Due At must be the same as or later than Started At.") }
        guard TimeZone(identifier: request.dueTimeZoneID) != nil else { throw DomainError("Choose a valid time zone for Due At.") }

        // One line per tool; the same tool twice is merged before checking stock.
        var order: [UUID] = []
        var wanted: [UUID: Int] = [:]
        for line in request.lines {
            guard line.quantity > 0 else { throw DomainError("Every quantity must be a whole number greater than zero.") }
            if wanted[line.toolID] == nil { order.append(line.toolID) }
            wanted[line.toolID, default: 0] += line.quantity
        }
        guard !order.isEmpty else { throw DomainError("Add at least one tool to check out.") }

        return try repository.transact { workshop in
            let balances = StockLedger.balances(workshop)
            var lines: [HandoverLine] = []
            for toolID in order {
                guard let tool = workshop.tool(toolID) else { throw DomainError.toolMissing }
                guard !tool.isArchived else { throw DomainError("\(tool.name) is archived and cannot be checked out.") }
                let quantity = wanted[toolID] ?? 0
                let available = balances[toolID]?.available ?? 0
                guard quantity <= available else {
                    throw DomainError(available == 0
                        ? "\(tool.name): none Available now. Nothing was checked out."
                        : "\(tool.name): only \(available) Available now, \(quantity) requested. Nothing was checked out.")
                }
                lines.append(HandoverLine(id: UUID(), toolID: toolID, toolNameSnapshot: tool.name, quantity: quantity))
            }

            let kitName = request.kitID.flatMap { workshop.kit($0)?.name } ?? ""
            let handover = Handover(
                id: UUID(), operationID: request.operationID, mode: request.mode, purpose: purpose,
                recipientName: recipient, contactNote: contact, startedAt: request.startedAt, dueAt: request.dueAt,
                dueTimeZoneID: request.dueTimeZoneID, lines: lines, conditionOutNote: condition,
                preparationSummary: request.preparationSummary.trimmed, kitID: request.kitID,
                kitNameSnapshot: kitName, returns: [], createdAt: now, updatedAt: now
            )
            workshop.handovers.append(handover)
            if let runID = request.preparationRunID {
                workshop.preparations.removeAll { $0.id == runID }
            }
            let units = lines.reduce(0) { $0 + $1.quantity }
            let title = request.mode == .loan ? "Loaned to \(recipient)" : "Checked out for personal use"
            workshop.log(.checkout, at: now, title: title,
                         detail: "\(purpose) · \(StockLedger.unitWord(units)) in \(lines.count) \(lines.count == 1 ? "line" : "lines")",
                         tools: lines.map(\.toolID), handover: handover.id, kit: request.kitID)
            return handover
        }
    }

    // MARK: - Return

    /// Confirm Return: records a (possibly partial) return line by line. Working units go
    /// back to Available, damaged units open a service record, lost units leave the total.
    @discardableResult
    func recordReturn(_ request: ReturnRequest) throws -> Handover {
        let now = clock.now
        let note = try Validate.text(request.note, max: Limits.conditionNoteMax, field: "Return Note")
        guard request.returnedAt <= now else { throw DomainError("Returned At cannot be in the future.") }

        return try repository.transact { workshop in
            let index = try workshop.handoverIndex(request.handoverID)
            var handover = workshop.handovers[index]
            if handover.returns.contains(where: { $0.operationID == request.operationID }) {
                return handover
            }
            guard !handover.isClosed else { throw DomainError("Everything in this handover has already been returned.") }
            guard request.returnedAt >= handover.startedAt else {
                throw DomainError("Returned At cannot be earlier than the checkout (\(handover.startedAt.formatted(date: .abbreviated, time: .shortened))).")
            }

            var recordLines: [ReturnLine] = []
            for entry in request.lines where entry.total > 0 {
                guard entry.toAvailable >= 0, entry.needsService >= 0, entry.lost >= 0 else {
                    throw DomainError("Returned quantities cannot be negative.")
                }
                guard let line = handover.lines.first(where: { $0.id == entry.lineID }) else { throw DomainError.recordMissing }
                let outstanding = handover.outstanding(forLine: line)
                guard entry.total <= outstanding else {
                    throw DomainError("\(line.toolNameSnapshot): only \(outstanding) still out, \(entry.total) entered.")
                }
                let issue = try Validate.text(entry.issueNote, max: Limits.issueMax, field: "Issue")
                if entry.needsService > 0 && issue.isEmpty {
                    throw DomainError("\(line.toolNameSnapshot): describe what needs attention for the units going to Needs Service.")
                }
                recordLines.append(ReturnLine(lineID: line.id, toolID: line.toolID, returnedToAvailable: entry.toAvailable,
                                              needsService: entry.needsService, lost: entry.lost, issueNote: issue))
            }
            guard !recordLines.isEmpty else { throw DomainError("Enter at least one returned unit.") }

            let record = ReturnRecord(id: UUID(), operationID: request.operationID, returnedAt: request.returnedAt,
                                      recordedAt: now, note: note, lines: recordLines)
            handover.returns.append(record)
            handover.updatedAt = now
            workshop.handovers[index] = handover

            for line in recordLines {
                let name = workshop.toolName(line.toolID)
                if line.needsService > 0 {
                    let service = ServiceRecord(
                        id: UUID(), toolID: line.toolID, toolNameSnapshot: name, quantity: line.needsService,
                        issue: line.issueNote, notes: "", openedAt: request.returnedAt,
                        source: .handoverReturn(handoverID: handover.id, holder: handover.holderLabel),
                        resolutions: [], updatedAt: now
                    )
                    workshop.serviceRecords.append(service)
                    workshop.log(.serviceOpened, at: now, title: "\(name) → Needs Service",
                                 detail: "\(StockLedger.unitWord(line.needsService)) · \(line.issueNote)",
                                 tools: [line.toolID], handover: handover.id, service: service.id)
                }
                if line.lost > 0 {
                    workshop.movements.append(StockMovement(
                        id: UUID(), toolID: line.toolID, kind: .lost, quantity: line.lost,
                        reason: "Not returned from “\(handover.purpose)” (\(handover.holderLabel))",
                        at: request.returnedAt, handoverID: handover.id
                    ))
                    workshop.log(.lost, at: now, title: "\(name) −\(line.lost) lost",
                                 detail: "Not returned from “\(handover.purpose)”", tools: [line.toolID], handover: handover.id)
                }
            }

            let back = recordLines.reduce(0) { $0 + $1.returnedToAvailable }
            let service = recordLines.reduce(0) { $0 + $1.needsService }
            var parts: [String] = []
            if back > 0 { parts.append("\(back) to Available") }
            if service > 0 { parts.append("\(service) to Needs Service") }
            let lost = recordLines.reduce(0) { $0 + $1.lost }
            if lost > 0 { parts.append("\(lost) lost") }
            let remaining = handover.totalOutstanding
            parts.append(remaining == 0 ? "all returned" : "\(remaining) still out")
            workshop.log(.returned, at: now,
                         title: remaining == 0 ? "Returned: \(handover.purpose)" : "Partial return: \(handover.purpose)",
                         detail: parts.joined(separator: " · "), tools: recordLines.map(\.toolID), handover: handover.id)
            return handover
        }
    }

    // MARK: - Due date

    func changeDue(_ handoverID: UUID, dueAt: Date, timeZoneID: String) throws {
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.handoverIndex(handoverID)
            let handover = workshop.handovers[index]
            guard !handover.isClosed else { throw DomainError("This handover is already returned.") }
            guard dueAt >= handover.startedAt else { throw DomainError("Due At must be the same as or later than Started At.") }
            guard TimeZone(identifier: timeZoneID) != nil else { throw DomainError("Choose a valid time zone.") }
            workshop.handovers[index].dueAt = dueAt
            workshop.handovers[index].dueTimeZoneID = timeZoneID
            workshop.handovers[index].updatedAt = now
            workshop.log(.dueChanged, at: now, title: "Due date changed: \(handover.purpose)",
                         detail: dueAt.formatted(date: .abbreviated, time: .shortened), handover: handoverID)
        }
    }
}

/// Plain-text summary the owner can share by their own choice after saving.
enum HandoverSummary {
    static func text(_ handover: Handover, now: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = handover.dueTimeZone

        var out: [String] = []
        out.append(handover.mode == .loan ? "Loan: \(handover.purpose)" : "Personal Use: \(handover.purpose)")
        if handover.mode == .loan { out.append("Recipient: \(handover.recipientName)") }
        formatter.timeZone = .current
        out.append("Started: \(formatter.string(from: handover.startedAt))")
        formatter.timeZone = handover.dueTimeZone
        let zone = handover.dueTimeZone.abbreviation(for: handover.dueAt) ?? handover.dueTimeZoneID
        out.append("Due: \(formatter.string(from: handover.dueAt)) \(zone)")
        out.append("")
        for line in handover.lines {
            let outstanding = handover.outstanding(forLine: line)
            let state = outstanding == 0 ? "returned" : "\(outstanding) still out"
            out.append("• \(line.toolNameSnapshot) × \(line.quantity) — \(state)")
        }
        if let note = handover.conditionOutNote.nilIfBlank {
            out.append("")
            out.append("Condition out: \(note)")
        }
        out.append("")
        switch handover.status(at: now) {
        case .returned: out.append("Status: Returned")
        case .overdue: out.append("Status: Overdue")
        case .open: out.append("Status: Open")
        }
        return out.joined(separator: "\n")
    }
}
