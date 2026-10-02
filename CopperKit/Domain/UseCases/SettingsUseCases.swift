import Foundation

final class SettingsUseCases {
    private let repository: WorkshopRepository
    private let photos: PhotoStoring

    init(repository: WorkshopRepository, photos: PhotoStoring) {
        self.repository = repository
        self.photos = photos
    }

    func update(_ settings: AppSettings) throws {
        guard Limits.loanDays.contains(settings.defaultLoanDays) else {
            throw DomainError("Default loan length must be from \(Limits.loanDays.lowerBound) to \(Limits.loanDays.upperBound) days.")
        }
        try CostRules.validateCurrency(settings.defaultCurrencyCode)
        try repository.transact { workshop in
            workshop.settings = settings
        }
    }

    /// Delete All Data: every record, every photo and the history. Settings survive so
    /// the app still works the way the owner set it up.
    func deleteAll() throws {
        let settings = repository.workshop.settings
        var empty = Workshop()
        empty.settings = settings
        try repository.replaceAll(with: empty)
        photos.deleteAll()
    }
}

/// CSV exports the owner can share by their own choice.
enum WorkshopExport {
    static func toolsCSV(_ workshop: Workshop) -> String {
        let balances = StockLedger.balances(workshop)
        var rows = [["Name", "Category", "Tracking", "Own Label", "Serial Number", "Home Location", "Total", "Available",
                     "In Use", "On Loan", "Needs Service", "Archived"]]
        for tool in workshop.tools.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let balance = balances[tool.id] ?? .zero
            rows.append([
                tool.name, tool.category.rawValue, tool.trackingMode.rawValue, tool.ownLabel, tool.serialNumber,
                workshop.location(tool.homeLocationID)?.name ?? "", "\(balance.total)", "\(balance.available)",
                "\(balance.inUse)", "\(balance.onLoan)", "\(balance.needsService)", tool.isArchived ? "yes" : "no"
            ])
        }
        return csv(rows)
    }

    static func handoversCSV(_ workshop: Workshop, now: Date) -> String {
        let iso = ISO8601DateFormatter()
        var rows = [["Purpose", "Mode", "Recipient", "Started At", "Due At", "Due Time Zone", "Tool", "Quantity Out",
                     "Returned to Available", "Needs Service", "Lost", "Outstanding", "Status"]]
        for handover in workshop.handovers.sorted(by: { $0.startedAt > $1.startedAt }) {
            for line in handover.lines {
                let back = handover.returned(forLine: line.id)
                rows.append([
                    handover.purpose, handover.mode.rawValue, handover.recipientName,
                    iso.string(from: handover.startedAt), iso.string(from: handover.dueAt), handover.dueTimeZoneID,
                    line.toolNameSnapshot, "\(line.quantity)", "\(back.available)", "\(back.needsService)",
                    "\(back.lost)", "\(handover.outstanding(forLine: line))", handover.status(at: now).rawValue
                ])
            }
        }
        return csv(rows)
    }

    /// RFC 4180 quoting, plus a leading apostrophe on cells a spreadsheet would treat as a formula.
    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                var value = cell
                if let first = value.first, "=+-@".contains(first) { value = "'" + value }
                if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                    value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return value
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}
