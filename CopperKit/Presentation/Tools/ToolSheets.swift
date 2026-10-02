import SwiftUI

/// Adjust Stock: a positive quantity, a direction and a reason, recorded as an event.
struct AdjustStockSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let toolID: UUID

    @State private var direction: StockAdjustmentDirection = .increase
    @State private var quantity = 1
    @State private var reason = ""
    @State private var error: String?

    var body: some View {
        let balance = store.balance(toolID)
        let tool = store.workshop.tool(toolID)
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                Text(tool?.name ?? "")
                    .font(CKFont.title)
                    .foregroundColor(CK.Palette.ink)
                UnitRack(balance: balance)
                CKSegmented(selection: $direction, options: StockAdjustmentDirection.allCases) {
                    $0 == .increase ? "Increase" : "Decrease"
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(label: "Quantity", required: true)
                    QuantityStepper(value: $quantity, range: Limits.quantity)
                    Text(direction == .increase
                         ? (tool?.trackingMode == .individual ? "An individual tool is always one unit; it can only come back to 1 after reaching 0." : "Adds units to Available.")
                         : "Only Available units can be removed (\(balance.available) now). Units that are out or in service must come back first.")
                        .font(CKFont.caption)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CKTextField(label: "Reason", text: $reason,
                            placeholder: direction == .increase ? "Bought two more" : "Broken beyond repair",
                            required: true, limit: Limits.reasonMax)
                Text("Recorded with today's date and time. Past events are never changed.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            .navigationTitle("Adjust Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.tools.adjustStock(toolID: toolID, direction: direction, quantity: quantity, reason: reason)
                            store.showToast(direction == .increase ? "Added \(Format.units(quantity))" : "Removed \(Format.units(quantity))")
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                }
            }
        }
    }
}

/// Send to Service: set Available units aside at home with a note of what's wrong.
struct SendToServiceSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let toolID: UUID

    @State private var quantity = 1
    @State private var issue = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        let available = store.balance(toolID).available
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                Text(store.workshop.toolName(toolID))
                    .font(CKFont.title)
                    .foregroundColor(CK.Palette.ink)
                Text("Units set aside here stay at home but aren't offered as Available until you return them.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(label: "Quantity", required: true)
                    QuantityStepper(value: $quantity, range: 1...max(1, available))
                    Text("\(available) Available")
                        .font(CKFont.caption)
                        .foregroundColor(CK.Palette.inkSecondary)
                }
                CKTextField(label: "Issue", text: $issue, placeholder: "Chuck slips, blade dull…", required: true,
                            limit: Limits.issueMax)
                CKTextArea(label: "Notes", text: $notes, limit: Limits.notesMax, minHeight: 80)
            }
            .navigationTitle("Send to Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.service.open(toolID: toolID, quantity: quantity, issue: issue, notes: notes)
                            store.showToast("\(Format.units(quantity)) set aside for service")
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                    .disabled(available == 0)
                }
            }
        }
    }
}

/// Moves one or more tools to a new Home Location (creating one if needed).
struct MoveToolsSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let toolIDs: [UUID]
    var onDone: (() -> Void)?

    @State private var target: UUID?
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            CKScroll(spacing: CK.Space.s) {
                if let error { NoticeView(text: error, tone: .error) }
                Text(toolIDs.count == 1 ? store.workshop.toolName(toolIDs[0]) : "\(toolIDs.count) tools")
                    .font(CKFont.title)
                    .foregroundColor(CK.Palette.ink)
                Text("Units at home move with the record. Units that are out keep their handover and return to the new place.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(store.sortedLocations) { location in
                    Button {
                        target = location.id
                    } label: {
                        HStack {
                            Image(systemName: target == location.id ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(target == location.id ? CK.Palette.copper : CK.Palette.inkSecondary)
                            VStack(alignment: .leading) {
                                Text(location.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                                let detail = [location.roomZone.nilIfBlank, location.shelfLabel.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
                                if !detail.isEmpty {
                                    Text(detail).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(CK.Space.s)
                        .frame(minHeight: CK.Size.button)
                        .background(RoundedRectangle(cornerRadius: CK.Radius.control).fill(CK.Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: CK.Radius.control)
                            .strokeBorder(target == location.id ? CK.Palette.copper : CK.Palette.hairline, lineWidth: target == location.id ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(target == location.id ? [.isSelected] : [])
                }
                Button { creating = true } label: { Label("Create Location", systemImage: "plus") }
                    .buttonStyle(CKTextButtonStyle())
            }
            .navigationTitle("Move Home Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        guard let target else { return }
                        do {
                            try store.tools.moveHome(toolIDs, to: target)
                            store.showToast("Moved to \(store.workshop.location(target)?.name ?? "")")
                            onDone?()
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                    .disabled(target == nil)
                }
            }
            .sheet(isPresented: $creating) {
                LocationEditorView(locationID: nil) { location in target = location.id }
                    .environmentObject(store)
            }
        }
        .onAppear {
            if toolIDs.count == 1 { target = store.workshop.tool(toolIDs[0])?.homeLocationID }
        }
    }
}

/// Add to Kit: choose a template; a tool already in it offers a quantity change instead.
struct AddToKitSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let tool: Tool

    @State private var selectedKit: UUID?
    @State private var quantity = 1
    @State private var creatingKit = false
    @State private var error: String?

    private var kits: [KitTemplate] {
        store.workshop.kits.filter { !$0.isArchived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            CKScroll(spacing: CK.Space.s) {
                if let error { NoticeView(text: error, tone: .error) }
                Text(tool.name).font(CKFont.title).foregroundColor(CK.Palette.ink)
                if kits.isEmpty {
                    Text("No kit templates yet.")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.inkSecondary)
                }
                ForEach(kits) { kit in
                    kitRow(kit)
                }
                Button { creatingKit = true } label: { Label("New Kit with This Tool", systemImage: "plus") }
                    .buttonStyle(CKSecondaryButtonStyle())
            }
            .navigationTitle("Add to Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $creatingKit) {
                KitEditorView(kitID: nil, initialTools: [tool.id]) { _ in dismiss() }
                    .environmentObject(store)
            }
        }
    }

    private func kitRow(_ kit: KitTemplate) -> some View {
        let existing = kit.lines.first { $0.toolID == tool.id }
        let isSelected = selectedKit == kit.id
        return VStack(alignment: .leading, spacing: CK.Space.s) {
            Button {
                selectedKit = isSelected ? nil : kit.id
                quantity = existing?.requiredQuantity ?? 1
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kit.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                        Text(existing.map { "Already in this kit × \($0.requiredQuantity)" } ?? "\(kit.lines.count) tools")
                            .font(CKFont.footnote)
                            .foregroundColor(existing == nil ? CK.Palette.inkSecondary : CK.Palette.copper)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .foregroundColor(CK.Palette.copper)
                }
                .frame(minHeight: CK.Size.button)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack {
                    QuantityStepper(value: $quantity, range: Limits.quantity, label: "Required Quantity")
                    Spacer()
                    Button(existing == nil ? "Add" : "Change Quantity") { save(kit) }
                        .buttonStyle(CKPrimaryButtonStyle(fullWidth: false))
                }
            }
        }
        .padding(.horizontal, CK.Space.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card).strokeBorder(isSelected ? CK.Palette.copper : CK.Palette.hairline, lineWidth: 1))
    }

    private func save(_ kit: KitTemplate) {
        var draft = KitDraft(kit: kit)
        if let index = draft.lines.firstIndex(where: { $0.toolID == tool.id }) {
            draft.lines[index].requiredQuantity = quantity
        } else {
            draft.lines.append(.init(toolID: tool.id, requiredQuantity: quantity))
        }
        do {
            try store.kits.save(draft, id: kit.id)
            store.showToast("\(tool.name) × \(quantity) in \(kit.name)")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
