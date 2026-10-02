import Foundation

/// Personal Use and Loan move units out of the workshop the same way and both must
/// come back; they differ only in who has them and how they are counted.
enum HandoverMode: String, CaseIterable, Hashable {
    case personalUse
    case loan
}

struct HandoverLine: Identifiable, Equatable, Hashable {
    let id: UUID
    var toolID: UUID
    var toolNameSnapshot: String
    var quantity: Int
}

/// What came back for one line in one return.
struct ReturnLine: Equatable, Hashable {
    var lineID: UUID
    var toolID: UUID
    /// Units back in working order — they become Available again.
    var returnedToAvailable: Int
    /// Units back but damaged — they go straight to Needs Service.
    var needsService: Int
    /// Units that will not come back — removed from the total.
    var lost: Int
    var issueNote: String

    var total: Int { returnedToAvailable + needsService + lost }
}

/// One confirmed return. A handover can be returned in several parts.
struct ReturnRecord: Identifiable, Equatable, Hashable {
    let id: UUID
    /// Idempotency key: a repeated tap with the same key records nothing new.
    var operationID: UUID
    var returnedAt: Date
    var recordedAt: Date
    var note: String
    var lines: [ReturnLine]
}

enum HandoverStatus: String, Hashable {
    case open
    case overdue
    case returned
}

struct Handover: Identifiable, Equatable, Hashable {
    let id: UUID
    /// Idempotency key of the checkout that created it.
    var operationID: UUID
    var mode: HandoverMode
    var purpose: String
    var recipientName: String
    var contactNote: String
    var startedAt: Date
    var dueAt: Date
    /// The time zone the due date was entered in, so it reads the same after travel.
    var dueTimeZoneID: String
    var lines: [HandoverLine]
    var conditionOutNote: String
    var preparationSummary: String
    var kitID: UUID?
    var kitNameSnapshot: String
    var returns: [ReturnRecord]
    var createdAt: Date
    var updatedAt: Date
}

extension Handover {
    func returned(forLine lineID: UUID) -> (available: Int, needsService: Int, lost: Int) {
        var result = (available: 0, needsService: 0, lost: 0)
        for record in returns {
            for line in record.lines where line.lineID == lineID {
                result.available += line.returnedToAvailable
                result.needsService += line.needsService
                result.lost += line.lost
            }
        }
        return result
    }

    func outstanding(forLine line: HandoverLine) -> Int {
        let back = returned(forLine: line.id)
        return max(0, line.quantity - back.available - back.needsService - back.lost)
    }

    var totalOut: Int { lines.reduce(0) { $0 + $1.quantity } }

    var totalOutstanding: Int { lines.reduce(0) { $0 + outstanding(forLine: $1) } }

    var isClosed: Bool { totalOutstanding == 0 }

    /// When the last unit came back, if everything has.
    var closedAt: Date? {
        guard isClosed else { return nil }
        return returns.map(\.returnedAt).max() ?? startedAt
    }

    func status(at now: Date) -> HandoverStatus {
        if isClosed { return .returned }
        return now > dueAt ? .overdue : .open
    }

    var dueTimeZone: TimeZone { TimeZone(identifier: dueTimeZoneID) ?? .current }

    /// "Anna" for a loan, "Personal Use" otherwise.
    var holderLabel: String {
        mode == .loan ? recipientName : "Personal Use"
    }
}
