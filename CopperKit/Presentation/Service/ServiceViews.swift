import SwiftUI

/// Service: units set aside at home until they're fixed or written off.
struct ServiceListView: View {
    @EnvironmentObject private var store: WorkshopStore

    private enum Filter: String, CaseIterable { case open = "Open", closed = "Closed" }
    @State private var filter: Filter = .open

    var body: some View {
        let records = sortedRecords
        CKScroll(spacing: CK.Space.s) {
            CKSegmented(selection: $filter, options: Filter.allCases) { $0.rawValue }
            if records.isEmpty {
                EmptyStateView(asset: "ck12_service_tray", assetSize: CGSize(width: 100, height: 90),
                               title: filter == .open ? "Nothing Needs Service" : "No Closed Records",
                               message: filter == .open
                                ? "Damaged units from a return, or anything you set aside from a tool page, appear here until they're back in Available."
                                : "Records move here once every unit is returned to Available or written off.")
            }
            ForEach(records) { record in
                NavigationLink(destination: ServiceRecordView(recordID: record.id)) {
                    ServiceRow(record: record, showsTool: true)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Open records oldest first (longest waiting on top); closed records newest first.
    private var sortedRecords: [ServiceRecord] {
        let all = store.workshop.serviceRecords
        if filter == .open {
            return all.filter(\.isOpen).sorted { $0.openedAt < $1.openedAt }
        }
        return all.filter { !$0.isOpen }.sorted { lhs, rhs in
            let a: Date = lhs.closedAt ?? lhs.openedAt
            let b: Date = rhs.closedAt ?? rhs.openedAt
            return a > b
        }
    }
}

struct ServiceRow: View {
    let record: ServiceRecord
    var showsTool: Bool

    var body: some View {
        HStack(alignment: .top, spacing: CK.Space.s) {
            Image(systemName: UnitState.needsService.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: CK.Radius.thumb).fill(record.isOpen ? CK.Palette.needsService : CK.Palette.inkSecondary))
            VStack(alignment: .leading, spacing: 3) {
                if showsTool {
                    Text(record.toolNameSnapshot).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                }
                Text(record.issue)
                    .font(showsTool ? CKFont.subhead : CKFont.headline)
                    .foregroundColor(showsTool ? CK.Palette.inkSecondary : CK.Palette.ink)
                    .lineLimit(2)
                Text(sourceLine)
                    .font(CKFont.footnote)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if record.isOpen {
                    StatusBadge(.needsService, count: record.openQuantity)
                        .padding(.top, 2)
                } else {
                    TagView(text: "Closed", icon: "checkmark")
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundColor(CK.Palette.copper)
                .accessibilityHidden(true)
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).strokeBorder(CK.Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var sourceLine: String {
        switch record.source {
        case .manual: return "Set aside \(Format.date(record.openedAt))"
        case .handoverReturn(_, let holder): return "Returned damaged · \(holder) · \(Format.date(record.openedAt))"
        }
    }
}

struct ServiceRecordView: View {
    @EnvironmentObject private var store: WorkshopStore
    let recordID: UUID

    @State private var resolving: ServiceResolutionKind?
    @State private var editingNotes = false

    var body: some View {
        if let record = store.workshop.serviceRecord(recordID) {
            content(record)
        } else {
            EmptyStateView(asset: nil, title: "Record Removed", message: DomainError.serviceMissing.message)
                .background(CK.Palette.background.ignoresSafeArea())
        }
    }

    private func content(_ record: ServiceRecord) -> some View {
        CKScroll {
            VStack(alignment: .leading, spacing: 6) {
                if record.isOpen {
                    StatusBadge(.needsService, count: record.openQuantity)
                } else {
                    TagView(text: "Closed \(record.closedAt.map(Format.date) ?? "")", icon: "checkmark")
                }
                Text(record.issue).font(CKFont.title).foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CKCard {
                if store.workshop.tool(record.toolID) != nil {
                    NavigationLink(destination: ToolDetailView(toolID: record.toolID)) {
                        HStack {
                            CKLabel("tool")
                            Spacer()
                            Text(record.toolNameSnapshot).font(CKFont.body.weight(.semibold)).foregroundColor(CK.Palette.velvet)
                        }
                        .frame(minHeight: 32)
                    }
                } else {
                    KeyValueRow(key: "tool", value: record.toolNameSnapshot)
                }
                KeyValueRow(key: "units", value: "\(record.quantity) set aside · \(record.openQuantity) still in service")
                KeyValueRow(key: "opened", value: Format.dateTime(record.openedAt))
                if case .handoverReturn(let handoverID, let holder) = record.source {
                    if store.workshop.handover(handoverID) != nil {
                        NavigationLink(destination: HandoverDetailView(handoverID: handoverID)) {
                            HStack {
                                CKLabel("from")
                                Spacer()
                                Text("Return from \(holder)").font(CKFont.body.weight(.semibold)).foregroundColor(CK.Palette.velvet)
                            }
                            .frame(minHeight: 32)
                        }
                    } else {
                        KeyValueRow(key: "from", value: "Return from \(holder)")
                    }
                }
            }

            if record.isOpen {
                Button { resolving = .returnedToAvailable } label: {
                    Label("Return to Available", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(CKPrimaryButtonStyle())
                Button { resolving = .writtenOff } label: {
                    Label("Write Off", systemImage: "trash")
                }
                .buttonStyle(CKDestructiveButtonStyle())
                Text("Write Off removes units that can't be repaired from the total. The history keeps them.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }

            CKSectionHeader(title: "Notes") {
                Button("Edit") { editingNotes = true }.buttonStyle(CKTextButtonStyle())
            }
            Text(record.notes.isEmpty ? "No notes." : record.notes)
                .font(CKFont.body)
                .foregroundColor(record.notes.isEmpty ? CK.Palette.inkSecondary : CK.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !record.resolutions.isEmpty {
                CKSectionHeader("Resolved")
                CKCard(padding: CK.Space.s) {
                    ForEach(Array(record.resolutions.sorted { $0.at > $1.at }.enumerated()), id: \.element.id) { index, resolution in
                        if index > 0 { CKDivider() }
                        HStack(alignment: .top) {
                            Image(systemName: resolution.kind == .returnedToAvailable ? "checkmark.circle.fill" : "trash.circle.fill")
                                .foregroundColor(resolution.kind == .returnedToAvailable ? CK.Palette.available : CK.Palette.overdue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolution.kind == .returnedToAvailable
                                     ? "\(Format.units(resolution.quantity)) returned to Available"
                                     : "\(Format.units(resolution.quantity)) written off")
                                    .font(CKFont.subhead.weight(.semibold))
                                    .foregroundColor(CK.Palette.ink)
                                if !resolution.note.isEmpty {
                                    Text(resolution.note).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
                                }
                            }
                            Spacer()
                            Text(Format.date(resolution.at)).font(CKFont.caption).foregroundColor(CK.Palette.inkSecondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Service Record")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $resolving) { kind in
            ResolveServiceSheet(record: record, kind: kind).environmentObject(store)
        }
        .sheet(isPresented: $editingNotes) {
            ServiceNotesSheet(record: record).environmentObject(store)
        }
    }
}

extension ServiceResolutionKind: Identifiable {
    var id: String { rawValue }
}

private struct ResolveServiceSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let record: ServiceRecord
    let kind: ServiceResolutionKind

    @State private var quantity = 1
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                Text(record.toolNameSnapshot).font(CKFont.title).foregroundColor(CK.Palette.ink)
                Text(kind == .returnedToAvailable
                     ? "These units are fixed or checked and can be handed out again."
                     : "These units can't be repaired. They leave the total; the history keeps them.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(label: "Quantity", required: true)
                    QuantityStepper(value: $quantity, range: 1...max(1, record.openQuantity))
                    Text("\(record.openQuantity) still in service").font(CKFont.caption).foregroundColor(CK.Palette.inkSecondary)
                }
                CKTextField(label: kind == .writtenOff ? "Reason" : "Note", text: $note,
                            placeholder: kind == .writtenOff ? "Motor burnt out" : "Replaced the blade",
                            required: kind == .writtenOff, limit: Limits.reasonMax)
            }
            .navigationTitle(kind == .returnedToAvailable ? "Return to Available" : "Write Off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == .returnedToAvailable ? "Return" : "Write Off") {
                        do {
                            try store.service.resolve(record.id, kind: kind, quantity: quantity, note: note)
                            store.showToast(kind == .returnedToAvailable ? "\(Format.units(quantity)) back in Available" : "\(Format.units(quantity)) written off")
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                }
            }
        }
        .onAppear { quantity = max(1, record.openQuantity) }
    }
}

private struct ServiceNotesSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let record: ServiceRecord
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                CKTextArea(label: "Notes", text: $notes, limit: Limits.notesMax, minHeight: 160)
            }
            .navigationTitle("Service Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.service.updateNotes(record.id, notes: notes)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                }
            }
        }
        .onAppear { notes = record.notes }
    }
}
