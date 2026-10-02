import Foundation

/// Where every unit of one tool record is right now.
struct ToolBalance: Equatable, Hashable {
    var total: Int = 0
    var inUse: Int = 0
    var onLoan: Int = 0
    var needsService: Int = 0

    /// Whatever exists and is neither out nor set aside.
    var available: Int { total - inUse - onLoan - needsService }
    /// Physically at home: ready units plus units set aside for service.
    var atHome: Int { available + needsService }
    var out: Int { inUse + onLoan }
    var isOutOfStock: Bool { total == 0 }

    static let zero = ToolBalance()
}

/// Derives every quantity in the app from the workshop document.
///
/// Total comes only from stock movements. Open handovers hold units In Use or On Loan,
/// open service records hold units in Needs Service, and Available is what is left.
/// Because nothing else is stored, no screen can disagree with another.
enum StockLedger {
    static func balances(_ workshop: Workshop) -> [UUID: ToolBalance] {
        var result: [UUID: ToolBalance] = [:]
        for tool in workshop.tools { result[tool.id] = .zero }
        for movement in workshop.movements {
            result[movement.toolID, default: .zero].total += movement.signedQuantity
        }
        for handover in workshop.handovers where !handover.isClosed {
            for line in handover.lines {
                let outstanding = handover.outstanding(forLine: line)
                guard outstanding > 0 else { continue }
                switch handover.mode {
                case .personalUse: result[line.toolID, default: .zero].inUse += outstanding
                case .loan: result[line.toolID, default: .zero].onLoan += outstanding
                }
            }
        }
        for record in workshop.serviceRecords where record.isOpen {
            result[record.toolID, default: .zero].needsService += record.openQuantity
        }
        return result
    }

    static func balance(of toolID: UUID, in workshop: Workshop) -> ToolBalance {
        balances(workshop)[toolID] ?? .zero
    }

    /// Workshop-wide figures for Home.
    static func summary(_ workshop: Workshop, now: Date) -> WorkshopSummary {
        // Archived records are out of the working catalogue; archiving requires nothing
        // out or in service, so their units only ever sit in Total/Available.
        let all = balances(workshop)
        var summary = WorkshopSummary()
        for tool in workshop.tools where !tool.isArchived {
            summary.toolRecords += 1
            let balance = all[tool.id] ?? .zero
            summary.totalUnits += balance.total
            summary.availableUnits += balance.available
            summary.inUse += balance.inUse
            summary.onLoan += balance.onLoan
            summary.needsService += balance.needsService
        }
        summary.openHandovers = workshop.handovers.filter { !$0.isClosed }.count
        summary.overdueHandovers = workshop.handovers.filter { $0.status(at: now) == .overdue }.count
        return summary
    }

    /// Everything that stops a tool from being archived, as sentences.
    static func archiveBlockers(toolID: UUID, in workshop: Workshop, now: Date) -> [String] {
        var blockers: [String] = []
        for handover in workshop.handovers where !handover.isClosed {
            for line in handover.lines where line.toolID == toolID {
                let outstanding = handover.outstanding(forLine: line)
                guard outstanding > 0 else { continue }
                let holder = handover.mode == .loan ? "on loan to \(handover.recipientName)" : "in personal use"
                blockers.append("\(unitWord(outstanding)) \(holder) for “\(handover.purpose)”. Record the return first.")
            }
        }
        for record in workshop.serviceRecords where record.toolID == toolID && record.isOpen {
            blockers.append("\(unitWord(record.openQuantity)) in Needs Service: “\(record.issue)”. Return to Available or write off first.")
        }
        return blockers
    }

    /// True once anything other than the initial quantity has happened to the tool.
    static func hasMovements(toolID: UUID, in workshop: Workshop) -> Bool {
        if workshop.movements.contains(where: { $0.toolID == toolID && $0.kind != .initial }) { return true }
        if workshop.handovers.contains(where: { $0.lines.contains { $0.toolID == toolID } }) { return true }
        if workshop.serviceRecords.contains(where: { $0.toolID == toolID }) { return true }
        if workshop.inventoryChecks.contains(where: { $0.lines.contains { $0.toolID == toolID } }) { return true }
        return false
    }

    static func unitWord(_ count: Int) -> String {
        count == 1 ? "1 unit" : "\(count) units"
    }
}

struct WorkshopSummary: Equatable {
    var toolRecords = 0
    var totalUnits = 0
    var availableUnits = 0
    var inUse = 0
    var onLoan = 0
    var needsService = 0
    var openHandovers = 0
    var overdueHandovers = 0
}
