import Foundation

/// One requirement of a kit template: this tool, this many units.
/// The template stores a need, never a reservation.
struct KitLine: Identifiable, Equatable, Hashable {
    let id: UUID
    var toolID: UUID
    /// The tool's name when the line was last saved, so a deleted tool still reads sensibly.
    var toolNameSnapshot: String
    var requiredQuantity: Int
}

struct KitTemplate: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var purpose: String
    var lines: [KitLine]
    var preparationNote: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isArchived: Bool { archivedAt != nil }
}

/// One line of a preparation run. Changes here belong to this run only; the template is
/// untouched unless the owner explicitly updates it.
struct PreparationLine: Identifiable, Equatable, Hashable {
    let id: UUID
    /// The tool the template asked for, nil for a line added only for this run.
    var templateToolID: UUID?
    /// The tool that will actually be taken — the same tool, or a replacement.
    var toolID: UUID
    var toolNameSnapshot: String
    /// What the template requires (shown for reference).
    var requiredQuantity: Int
    /// What this run will take.
    var runQuantity: Int
    var isPrepared: Bool
    var isRemoved: Bool

    var isReplacement: Bool {
        guard let templateToolID else { return false }
        return templateToolID != toolID
    }
}

/// A saved preparation: a checklist being worked through before a checkout.
/// Ticking lines never moves stock — only Confirm Checkout does.
struct PreparationRun: Identifiable, Equatable, Hashable {
    let id: UUID
    var kitID: UUID?
    var title: String
    /// Set when the run repeats an earlier handover.
    var sourceHandoverID: UUID?
    var lines: [PreparationLine]
    var runNote: String
    var createdAt: Date
    var updatedAt: Date

    var activeLines: [PreparationLine] { lines.filter { !$0.isRemoved } }
}
