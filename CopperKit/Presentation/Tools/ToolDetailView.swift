import SwiftUI

/// Where every unit of one tool is: at home, out with whom, or set aside for service.
struct ToolDetailView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    let toolID: UUID

    private enum ActiveSheet: Identifiable {
        case edit, adjust, service, move, addToKit, checkout
        var id: Int { hashValue }
    }

    @State private var sheet: ActiveSheet?
    @State private var showsCost = false
    @State private var confirmDelete = false
    @State private var confirmArchive = false

    var body: some View {
        if let tool = store.workshop.tool(toolID) {
            content(tool)
        } else {
            EmptyStateView(asset: nil, title: "Tool Removed", message: DomainError.toolMissing.message)
                .background(CK.Palette.background.ignoresSafeArea())
        }
    }

    private func content(_ tool: Tool) -> some View {
        let balance = store.balance(tool.id)
        return CKScroll {
            photos(tool)
            titleBlock(tool)
            quantityCard(tool, balance)
            actionButtons(tool, balance)
            locationCard(tool)
            activeHandovers(tool)
            serviceRecords(tool)
            costCard(tool)
            if !tool.notes.isEmpty {
                CKSectionHeader("Notes")
                CKCard {
                    Text(tool.notes)
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            timeline(tool)
            manageSection(tool, balance)
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { sheet = .edit }
                    .font(CKFont.button)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .edit:
                ToolEditorView(mode: .edit(tool.id))
                    .environmentObject(store)
            case .adjust:
                AdjustStockSheet(toolID: tool.id).environmentObject(store)
            case .service:
                SendToServiceSheet(toolID: tool.id).environmentObject(store)
            case .move:
                MoveToolsSheet(toolIDs: [tool.id]).environmentObject(store)
            case .addToKit:
                AddToKitSheet(tool: tool).environmentObject(store)
            case .checkout:
                CheckoutReviewView(source: .tool(tool.id)) { handover in
                    router.openHandover(handover.id)
                }
                .environmentObject(store)
            }
        }
        .confirmationDialog("Delete \(tool.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Tool", role: .destructive) {
                var photoIDs: [String] = []
                if store.perform("Can't Delete", { photoIDs = try store.tools.delete(tool.id) }) {
                    store.photos.delete(photoIDs)
                    store.showToast("\(tool.name) deleted")
                    dismiss()
                }
            }
        } message: {
            Text("This record has no history, so it can be removed completely. Kits that list it will show Needs Review.")
        }
        .confirmationDialog("Archive \(tool.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive") {
                if store.perform("Can't Archive", { try store.tools.archive(tool.id) }) {
                    store.showToast("\(tool.name) archived")
                }
            }
        } message: {
            Text("Archived tools keep their history but are not offered in new kits or checkouts. You can restore it later.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func photos(_ tool: Tool) -> some View {
        if tool.photoIDs.isEmpty {
            HStack(spacing: CK.Space.m) {
                Sprite("ck05_copper_hammer", size: CGSize(width: 112, height: 112))
                VStack(alignment: .leading, spacing: 4) {
                    Text("No photo yet")
                        .font(CKFont.headline)
                        .foregroundColor(CK.Palette.ink)
                    Text("The illustration is only a placeholder, not this model. Add your own photo in Edit.")
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            TabView {
                ForEach(tool.photoIDs, id: \.self) { id in
                    Group {
                        if let data = store.photos.load(id), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            ZStack {
                                CK.Palette.surfaceSunken
                                Text("Photo unavailable").font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel("Photo of \(tool.name)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: tool.photoIDs.count > 1 ? .always : .never))
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous))
        }
    }

    private func titleBlock(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tool.name)
                .font(CKFont.display)
                .foregroundColor(CK.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TagView(text: tool.category.title, icon: tool.category.icon, color: CK.Palette.copper)
                TagView(text: tool.trackingMode.title, color: CK.Palette.velvet)
                if tool.isArchived { TagView(text: "Archived", icon: "archivebox") }
            }
            if !tool.ownLabel.isEmpty || !tool.serialNumber.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !tool.ownLabel.isEmpty { KeyValueRow(key: "own label", value: tool.ownLabel) }
                    if !tool.serialNumber.isEmpty { KeyValueRow(key: "serial number", value: tool.serialNumber) }
                }
                .padding(.top, 4)
            }
        }
    }

    private func quantityCard(_ tool: Tool, _ balance: ToolBalance) -> some View {
        CKCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    (Text("\(balance.available)").foregroundColor(CK.Palette.ink)
                        + Text(" / \(balance.total)").foregroundColor(CK.Palette.inkSecondary))
                        .ckFigure(40)
                    CKLabel("available of total")
                }
                Spacer()
                if balance.isOutOfStock {
                    TagView(text: "Out of Stock", icon: "minus.circle", color: CK.Palette.overdue)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(balance.available) of \(balance.total) available\(balance.isOutOfStock ? ", out of stock" : "")")
            UnitRack(balance: balance)
        }
    }

    private func actionButtons(_ tool: Tool, _ balance: ToolBalance) -> some View {
        VStack(spacing: CK.Space.s) {
            Button {
                sheet = .checkout
            } label: {
                Label("Checkout", systemImage: "arrow.up.forward.circle.fill")
            }
            .buttonStyle(CKPrimaryButtonStyle())
            .disabled(tool.isArchived || balance.available == 0)
            if !tool.isArchived && balance.available == 0 {
                Text("Nothing Available to check out right now.")
                    .font(CKFont.footnote)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            HStack(spacing: CK.Space.s) {
                Button { sheet = .addToKit } label: { Label("Add to Kit", systemImage: "case") }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(tool.isArchived)
                Button { sheet = .service } label: { Label("Send to Service", systemImage: "wrench") }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(balance.available == 0)
            }
            Button { sheet = .adjust } label: { Label("Adjust Stock", systemImage: "plusminus") }
                .buttonStyle(CKSecondaryButtonStyle())
        }
    }

    private func locationCard(_ tool: Tool) -> some View {
        let location = store.workshop.location(tool.homeLocationID)
        return CKCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CKLabel("home location")
                    Text(location?.name ?? "Missing location")
                        .font(CKFont.headline)
                        .foregroundColor(CK.Palette.ink)
                    let detail = [location?.roomZone.nilIfBlank, location?.shelfLabel.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(CKFont.subhead).foregroundColor(CK.Palette.inkSecondary)
                    }
                }
                Spacer()
                Button("Move") { sheet = .move }
                    .buttonStyle(CKTextButtonStyle())
                    .accessibilityLabel("Move Home Location")
            }
            if let location {
                NavigationLink(destination: LocationDetailView(locationID: location.id)) {
                    Label("Open Location", systemImage: "archivebox")
                        .font(CKFont.subhead.weight(.semibold))
                        .foregroundColor(CK.Palette.velvet)
                        .frame(minHeight: 44)
                }
            }
            if store.balance(tool.id).out > 0 {
                Text("Units that are out keep their handover and come back here when the return is confirmed.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func activeHandovers(_ tool: Tool) -> some View {
        let open = store.workshop.handovers
            .filter { !$0.isClosed && $0.lines.contains { $0.toolID == tool.id } }
            .sorted { $0.dueAt < $1.dueAt }
        if !open.isEmpty {
            CKSectionHeader("Active Handovers")
            ForEach(open) { handover in
                NavigationLink(destination: HandoverDetailView(handoverID: handover.id)) {
                    HandoverRow(handover: handover, now: store.now, focusToolID: tool.id)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func serviceRecords(_ tool: Tool) -> some View {
        let records = store.workshop.serviceRecords.filter { $0.toolID == tool.id }.sorted { $0.openedAt > $1.openedAt }
        if !records.isEmpty {
            CKSectionHeader("Service Records")
            ForEach(records.prefix(4)) { record in
                NavigationLink(destination: ServiceRecordView(recordID: record.id)) {
                    ServiceRow(record: record, showsTool: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func costCard(_ tool: Tool) -> some View {
        if let cost = tool.purchaseCost {
            CKCard {
                HStack {
                    CKLabel("private purchase cost")
                    Spacer()
                    Button(showsCost ? "Hide Cost" : "Show Cost") { showsCost.toggle() }
                        .buttonStyle(CKTextButtonStyle())
                }
                if showsCost {
                    Text(Format.money(cost))
                        .font(CKFont.title3.monospacedDigit())
                        .foregroundColor(CK.Palette.ink)
                    Text(costNote(tool))
                        .font(CKFont.caption)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Hidden")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.inkSecondary)
                }
            }
        } else if tool.purchaseDate != nil {
            CKCard {
                KeyValueRow(key: "purchase date", value: Format.date(tool.purchaseDate!))
                KeyValueRow(key: "purchase cost", value: "Unknown", valueColor: CK.Palette.inkSecondary)
            }
        }
    }

    private func costNote(_ tool: Tool) -> String {
        var parts = ["For the whole batch"]
        if let date = tool.purchaseDate { parts.append("bought \(Format.date(date))") }
        parts.append("a personal note, not a valuation")
        return parts.joined(separator: " · ")
    }

    private func timeline(_ tool: Tool) -> some View {
        let events = store.workshop.activity.filter { $0.toolIDs.contains(tool.id) }.sorted { $0.at > $1.at }
        return VStack(alignment: .leading, spacing: CK.Space.s) {
            CKSectionHeader(title: "Timeline") {
                NavigationLink("Open History", destination: HistoryView(toolID: tool.id))
                    .font(CKFont.subhead.weight(.semibold))
                    .foregroundColor(CK.Palette.velvet)
                    .frame(minHeight: 44)
            }
            if events.isEmpty {
                Text("No events yet.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
            } else {
                CKCard(padding: CK.Space.s) {
                    ForEach(Array(events.prefix(6).enumerated()), id: \.element.id) { index, event in
                        if index > 0 { CKDivider() }
                        ActivityRow(event: event, now: store.now)
                    }
                }
            }
        }
    }

    private func manageSection(_ tool: Tool, _ balance: ToolBalance) -> some View {
        let blockers = StockLedger.archiveBlockers(toolID: tool.id, in: store.workshop, now: store.now)
        let canDelete = !StockLedger.hasMovements(toolID: tool.id, in: store.workshop)
        return VStack(alignment: .leading, spacing: CK.Space.s) {
            CKSectionHeader("Manage")
            if tool.isArchived {
                Button("Restore Tool") {
                    if store.perform("Can't Restore", { try store.tools.restore(tool.id) }) {
                        store.showToast("\(tool.name) restored")
                    }
                }
                .buttonStyle(CKSecondaryButtonStyle())
            } else {
                Button("Archive Tool") { confirmArchive = true }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(!blockers.isEmpty)
                if !blockers.isEmpty {
                    NoticeView(text: "Archive becomes available when nothing is open:\n" + blockers.map { "• \($0)" }.joined(separator: "\n"),
                               tone: .info)
                }
            }
            if canDelete {
                Button("Delete Tool") { confirmDelete = true }
                    .buttonStyle(CKDestructiveButtonStyle())
            } else {
                Text("This tool has history, so it can be archived but not deleted. Delete All Data in Settings removes everything.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
