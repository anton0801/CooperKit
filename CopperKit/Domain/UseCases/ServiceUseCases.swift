import Foundation

final class ServiceUseCases {
    private let repository: WorkshopRepository
    private let clock: Clock

    init(repository: WorkshopRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    /// Send to Service: sets Available units aside at home so they are not offered in
    /// the next kit.
    @discardableResult
    func open(toolID: UUID, quantity: Int, issue: String, notes: String) throws -> ServiceRecord {
        let now = clock.now
        let quantity = try Validate.quantity(quantity)
        let issue = try Validate.required(issue, max: Limits.issueMax, field: "Issue")
        let notes = try Validate.text(notes, max: Limits.notesMax, field: "Notes")
        return try repository.transact { workshop in
            let tool = workshop.tools[try workshop.toolIndex(toolID)]
            let available = StockLedger.balance(of: toolID, in: workshop).available
            guard quantity <= available else {
                throw DomainError(available == 0
                    ? "No units of \(tool.name) are Available to set aside."
                    : "Only \(StockLedger.unitWord(available)) of \(tool.name) Available to set aside.")
            }
            let record = ServiceRecord(id: UUID(), toolID: toolID, toolNameSnapshot: tool.name, quantity: quantity,
                                       issue: issue, notes: notes, openedAt: now, source: .manual,
                                       resolutions: [], updatedAt: now)
            workshop.serviceRecords.append(record)
            workshop.log(.serviceOpened, at: now, title: "\(tool.name) → Needs Service",
                         detail: "\(StockLedger.unitWord(quantity)) · \(issue)", tools: [toolID], service: record.id)
            return record
        }
    }

    /// Return to Available, or write off units that are beyond repair.
    func resolve(_ recordID: UUID, kind: ServiceResolutionKind, quantity: Int, note: String) throws {
        let now = clock.now
        let quantity = try Validate.positive(quantity)
        let note = try Validate.text(note, max: Limits.reasonMax, field: "Note")
        if kind == .writtenOff && note.isEmpty {
            throw DomainError("Add a reason for writing these units off.")
        }
        try repository.transact { workshop in
            let index = try workshop.serviceIndex(recordID)
            var record = workshop.serviceRecords[index]
            guard quantity <= record.openQuantity else {
                throw DomainError("Only \(StockLedger.unitWord(record.openQuantity)) still in service on this record.")
            }
            record.resolutions.append(ServiceResolution(id: UUID(), kind: kind, quantity: quantity, note: note, at: now))
            record.updatedAt = now
            workshop.serviceRecords[index] = record
            let name = workshop.toolName(record.toolID)
            switch kind {
            case .returnedToAvailable:
                workshop.log(.serviceResolved, at: now, title: "\(name) → Available",
                             detail: "\(StockLedger.unitWord(quantity)) back from service\(note.isEmpty ? "" : " · \(note)")",
                             tools: [record.toolID], service: recordID)
            case .writtenOff:
                workshop.movements.append(StockMovement(id: UUID(), toolID: record.toolID, kind: .writtenOff,
                                                        quantity: quantity, reason: note, at: now,
                                                        serviceRecordID: recordID))
                workshop.log(.serviceResolved, at: now, title: "\(name) −\(quantity) written off",
                             detail: note, tools: [record.toolID], service: recordID)
            }
        }
    }

    func updateNotes(_ recordID: UUID, notes: String) throws {
        let notes = try Validate.text(notes, max: Limits.notesMax, field: "Notes")
        let now = clock.now
        try repository.transact { workshop in
            let index = try workshop.serviceIndex(recordID)
            workshop.serviceRecords[index].notes = notes
            workshop.serviceRecords[index].updatedAt = now
        }
    }
}
