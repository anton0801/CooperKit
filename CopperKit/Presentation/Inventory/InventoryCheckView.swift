import SwiftUI

/// Inventory Check: count what is physically at home and compare it with the books.
/// Differences are applied as separate inventory events; nothing else is rewritten.
struct InventoryCheckView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let locationID: UUID?

    @State private var rows: [InventoryCountRow] = []
    @State private var counts: [UUID: Int] = [:]
    @State private var note = ""
    @State private var error: String?
    @State private var confirming = false
    @State private var loaded = false

    private var title: String {
        locationID.flatMap { store.workshop.location($0)?.name } ?? "All Locations"
    }

    var body: some View {
        let changes = rows.compactMap { row -> (InventoryCountRow, Int)? in
            guard let counted = counts[row.id], counted != row.expectedAtHome else { return nil }
            return (row, counted - row.expectedAtHome)
        }
        ScrollViewReader { proxy in
            CKScroll {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(CKFont.title).foregroundColor(CK.Palette.ink)
                    Text("Count what is physically here. Units that are out aren't expected. Leave a tool uncounted to skip it.")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error { NoticeView(text: error, tone: .error).id("error") }

                if rows.isEmpty {
                    Text("No tools to count here.")
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.inkSecondary)
                } else {
                    HStack {
                        Text("\(counts.count) of \(rows.count) counted")
                            .font(CKFont.footnote.monospacedDigit())
                            .foregroundColor(CK.Palette.inkSecondary)
                        Spacer()
                        Button("Fill Uncounted as Expected") {
                            for row in rows where counts[row.id] == nil { counts[row.id] = row.expectedAtHome }
                        }
                        .buttonStyle(CKTextButtonStyle())
                    }
                }

                ForEach(rows) { row in
                    rowCard(row)
                }

                if !rows.isEmpty {
                    CKTextArea(label: "Note", text: $note, limit: Limits.notesMax, minHeight: 64)
                    if !counts.isEmpty {
                        NoticeView(text: changes.isEmpty
                                   ? "Everything counted matches the books. Applying records the check with no changes."
                                   : "\(changes.count) \(changes.count == 1 ? "difference" : "differences") will be recorded as inventory adjustments.",
                                   tone: .info)
                    }
                    Button { confirming = true } label: { Label("Apply Adjustments", systemImage: "checkmark.seal.fill") }
                        .buttonStyle(CKPrimaryButtonStyle())
                        .disabled(counts.isEmpty)
                }

                pastChecks
            }
            .onChange(of: error) { value in if value != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } } }
        }
        .navigationTitle("Inventory Check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = store.inventory.rows(locationID: locationID)
        }
        .confirmationDialog("Apply this count?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply Adjustments") { apply() }
        } message: {
            Text(changes.isEmpty
                 ? "No differences. The check is saved to History."
                 : changes.map { "\($0.0.tool.name): \($0.1 > 0 ? "+" : "")\($0.1)" }.joined(separator: "\n"))
        }
    }

    private func rowCard(_ row: InventoryCountRow) -> some View {
        let counted = counts[row.id]
        let variance = counted.map { $0 - row.expectedAtHome }
        let balance = store.balance(row.id)
        return VStack(alignment: .leading, spacing: CK.Space.xs) {
            HStack(spacing: CK.Space.s) {
                ToolThumbnail(tool: row.tool, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.tool.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                    Text("Expected at home: \(row.expectedAtHome) (\(balance.available) ready, \(balance.needsService) service)")
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                    if row.out > 0 {
                        Text("\(row.out) out with a handover — not counted here")
                            .font(CKFont.footnote)
                            .foregroundColor(CK.Palette.inkSecondary)
                    }
                }
                Spacer()
            }
            HStack {
                if let counted {
                    QuantityStepper(value: Binding(get: { counted }, set: { counts[row.id] = $0 }),
                                    range: 0...Limits.quantity.upperBound, label: "Counted", compact: true)
                    Button("Skip") { counts[row.id] = nil }.buttonStyle(CKTextButtonStyle())
                } else {
                    Button("Count") { counts[row.id] = row.expectedAtHome }
                        .buttonStyle(CKSecondaryButtonStyle(fullWidth: false))
                }
                Spacer()
                if let variance {
                    if variance == 0 {
                        StatusBadge(title: "Matches", icon: "checkmark", fill: CK.Palette.available)
                    } else {
                        StatusBadge(title: variance > 0 ? "+\(variance) found" : "\(variance) missing",
                                    icon: variance > 0 ? "plus" : "minus",
                                    fill: variance > 0 ? CK.Palette.velvet : CK.Palette.overdue)
                    }
                } else {
                    TagView(text: "Not counted")
                }
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card).strokeBorder(CK.Palette.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var pastChecks: some View {
        let checks = store.workshop.inventoryChecks
            .filter { $0.locationID == locationID }
            .sorted { $0.performedAt > $1.performedAt }
            .prefix(3)
        if !checks.isEmpty {
            CKSectionHeader("Earlier Checks")
            ForEach(Array(checks)) { check in
                CKCard(padding: CK.Space.s) {
                    let changed = check.lines.filter { $0.variance != 0 }
                    Text(Format.dateTime(check.performedAt)).font(CKFont.subhead.weight(.semibold)).foregroundColor(CK.Palette.ink)
                    Text("\(check.lines.count) counted · \(changed.isEmpty ? "no differences" : "\(changed.count) adjusted")")
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                }
            }
        }
    }

    private func apply() {
        do {
            let check = try store.inventory.apply(locationID: locationID, counts: counts, note: note)
            let changed = check.lines.filter { $0.variance != 0 }.count
            store.showToast(changed == 0 ? "Inventory checked · no differences" : "Inventory applied · \(changed) adjusted")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
