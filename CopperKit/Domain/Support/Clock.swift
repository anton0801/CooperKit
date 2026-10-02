import Foundation

/// Supplies "now" as a dependency. Overdue, due dates and back-dated handovers are all
/// rules about time, so tests need to be able to fix it.
protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

struct FixedClock: Clock {
    var now: Date
}

extension String {
    /// The value with surrounding whitespace and newlines removed.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nil when the trimmed value is empty — used for optional text fields.
    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
