import Foundation

enum Format {
    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A due date shown in the zone it was entered in; the zone is named only when it
    /// differs from the device's.
    static func due(_ handover: Handover) -> String {
        let zone = handover.dueTimeZone
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = zone
        let text = formatter.string(from: handover.dueAt)
        if zone.identifier == TimeZone.current.identifier { return text }
        return "\(text) \(zone.abbreviation(for: handover.dueAt) ?? zone.identifier)"
    }

    static func relativeDue(_ due: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: due, relativeTo: now)
    }

    /// Amount and currency side by side, e.g. "1,299.00 EUR". Never styled as a win.
    static func money(_ cost: PurchaseCost) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(from: cost.amount as NSDecimalNumber) ?? "\(cost.amount)"
        return "\(amount) \(cost.currencyCode)"
    }

    static func units(_ count: Int) -> String {
        count == 1 ? "1 unit" : "\(count) units"
    }

    static func dayHeading(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(date: .complete, time: .omitted)
    }
}

extension ToolCategory {
    var title: String {
        switch self {
        case .powerTool: return "Power Tool"
        case .handTool: return "Hand Tool"
        case .measuring: return "Measuring"
        case .accessory: return "Accessory"
        case .toolCase: return "Case"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .powerTool: return "bolt.fill"
        case .handTool: return "hammer.fill"
        case .measuring: return "ruler.fill"
        case .accessory: return "paperclip"
        case .toolCase: return "case.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

extension TrackingMode {
    var title: String {
        switch self {
        case .individual: return "Individual"
        case .identicalUnits: return "Identical Units"
        }
    }

    var explanation: String {
        switch self {
        case .individual: return "One serialised tool. Always exactly one unit."
        case .identicalUnits: return "Interchangeable copies with one shared description. Different serial numbers need separate records."
        }
    }
}

extension HandoverMode {
    var title: String {
        switch self {
        case .personalUse: return "Personal Use"
        case .loan: return "Loan"
        }
    }
}

extension ActivityKind {
    var icon: String {
        switch self {
        case .toolAdded: return "plus.circle.fill"
        case .toolEdited: return "pencil.circle.fill"
        case .stockAdjusted: return "plusminus.circle.fill"
        case .toolMoved: return "arrow.right.circle.fill"
        case .toolArchived: return "archivebox.fill"
        case .toolRestored: return "arrow.uturn.backward.circle.fill"
        case .toolDeleted: return "trash.circle.fill"
        case .checkout: return "arrow.up.forward.circle.fill"
        case .returned: return "arrow.down.backward.circle.fill"
        case .lost: return "questionmark.circle.fill"
        case .dueChanged: return "calendar.circle.fill"
        case .serviceOpened: return "wrench.fill"
        case .serviceResolved: return "checkmark.circle.fill"
        case .inventoryApplied: return "checklist"
        case .locationAdded, .locationEdited, .locationDeleted: return "archivebox.circle.fill"
        case .kitSaved, .kitArchived, .kitRestored, .kitDeleted: return "case.fill"
        }
    }
}

extension ActivityGroup {
    var title: String {
        switch self {
        case .handovers: return "Handovers"
        case .service: return "Service"
        case .stock: return "Stock"
        case .tools: return "Tools"
        case .storage: return "Storage"
        case .kits: return "Kits"
        }
    }
}

/// Currency codes offered first in pickers; the full ISO list follows.
enum Currencies {
    static let common = ["USD", "EUR", "GBP", "CAD", "AUD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "JPY", "NZD"]

    static func all(including current: String) -> [String] {
        var list = common
        if !list.contains(current) { list.insert(current, at: 0) }
        let rest = NSLocale.commonISOCurrencyCodes.filter { !list.contains($0) }.sorted()
        return list + rest
    }
}
