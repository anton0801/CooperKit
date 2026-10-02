import SwiftUI

/// Kits tab: saved lists of what a recurring job needs.
struct KitListView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter

    private enum Scope: String, CaseIterable { case active = "Active", archived = "Archived" }
    @State private var scope: Scope = .active
    @State private var creating = false

    var body: some View {
        let kits = store.workshop.kits
            .filter { scope == .active ? !$0.isArchived : $0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        CKScroll(spacing: CK.Space.s) {
            if store.workshop.kits.isEmpty {
                EmptyStateView(asset: "ck08_tool_roll", assetSize: CGSize(width: 112, height: 80),
                               title: "Create a Kit Template",
                               message: "List what a recurring job needs once — then prepare it against what's actually Available.") {
                    Button { creating = true } label: { Label("Create Kit", systemImage: "plus") }
                        .buttonStyle(CKPrimaryButtonStyle())
                        .disabled(store.activeTools.isEmpty)
                    if store.activeTools.isEmpty {
                        Text("Add a tool first.")
                            .font(CKFont.footnote)
                            .foregroundColor(CK.Palette.inkSecondary)
                    }
                }
                .padding(.top, CK.Space.xl)
            } else {
                CKSegmented(selection: $scope, options: Scope.allCases) { $0.rawValue }
                if kits.isEmpty {
                    Text(scope == .archived ? "No archived kits." : "No active kits.")
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CK.Space.l)
                }
                ForEach(kits) { kit in
                    NavigationLink(destination: KitDetailView(kitID: kit.id)) {
                        KitRow(kit: kit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Kits")
        .toolbar {
            HomeToolbarItem(router: router)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { creating = true } label: {
                    Label("Create", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(CKFont.subhead.weight(.semibold))
                }
                .disabled(store.activeTools.isEmpty)
                .accessibilityLabel("Create Kit")
            }
        }
        .background(RouteLink(route: $router.kitRoute) { KitDetailView(kitID: $0) })
        .sheet(isPresented: $creating) {
            KitEditorView(kitID: nil).environmentObject(store)
        }
    }
}

private struct KitRow: View {
    @EnvironmentObject private var store: WorkshopStore
    let kit: KitTemplate

    var body: some View {
        let units = kit.lines.reduce(0) { $0 + $1.requiredQuantity }
        let review = KitRules.needsReview(kit, in: store.workshop)
        let ready = kit.lines.allSatisfy { store.balance($0.toolID).available >= $0.requiredQuantity && KitRules.issue(for: $0, in: store.workshop) == nil }
        let saved = store.workshop.preparations.contains { $0.kitID == kit.id && $0.sourceHandoverID == nil }
        return HStack(spacing: CK.Space.s) {
            Image(systemName: "case.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CK.Palette.gold)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: CK.Radius.thumb).fill(CK.Palette.deepBlue))
            VStack(alignment: .leading, spacing: 3) {
                Text(kit.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                if !kit.purpose.isEmpty {
                    Text(kit.purpose).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary).lineLimit(2)
                }
                Text("\(kit.lines.count) \(kit.lines.count == 1 ? "tool" : "tools") · \(Format.units(units))")
                    .font(CKFont.footnote)
                    .foregroundColor(CK.Palette.inkSecondary)
                HStack(spacing: 4) {
                    if review {
                        TagView(text: "Needs Review", icon: "exclamationmark.triangle", color: CK.Palette.needsService)
                    } else if !kit.isArchived {
                        if ready {
                            StatusBadge(title: "All Available", icon: "checkmark.circle.fill", fill: CK.Palette.available)
                        } else {
                            TagView(text: "Short Right Now", icon: "minus.circle", color: CK.Palette.needsService)
                        }
                    }
                    if saved { TagView(text: "Preparation Saved", icon: "bookmark", color: CK.Palette.velvet) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(CK.Palette.copper)
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).strokeBorder(CK.Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// One template: its needs against Available now, and Prepare.
struct KitDetailView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let kitID: UUID

    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        if let kit = store.workshop.kit(kitID) {
            content(kit)
        } else {
            EmptyStateView(asset: nil, title: "Kit Removed", message: DomainError.kitMissing.message)
                .background(CK.Palette.background.ignoresSafeArea())
        }
    }

    private func content(_ kit: KitTemplate) -> some View {
        CKScroll {
            VStack(alignment: .leading, spacing: 6) {
                Text(kit.name).font(CKFont.display).foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if kit.isArchived { TagView(text: "Archived", icon: "archivebox") }
                if !kit.purpose.isEmpty {
                    Text(kit.purpose).font(CKFont.body).foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !kit.isArchived {
                NavigationLink(destination: PrepareKitView(source: .kit(kit.id))) {
                    Label("Prepare", systemImage: "checklist")
                }
                .buttonStyle(CKPrimaryButtonStyle())
                Text("The template is a list of needs. It never reserves tools; availability is checked when you check out.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CKSectionHeader("Tools")
            CKCard(padding: CK.Space.s) {
                ForEach(Array(kit.lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { CKDivider() }
                    kitLineRow(line)
                }
            }

            if !kit.preparationNote.isEmpty {
                CKSectionHeader("Preparation Note")
                CKCard {
                    Text(kit.preparationNote).font(CKFont.body).foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CKSectionHeader("Manage")
            HStack(spacing: CK.Space.s) {
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(CKSecondaryButtonStyle())
                Button {
                    if store.perform("Can't Duplicate", { _ = try store.kits.duplicate(kit.id) }) {
                        store.showToast("Duplicated \(kit.name)")
                    }
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .buttonStyle(CKSecondaryButtonStyle())
            }
            Button(kit.isArchived ? "Restore Kit" : "Archive Kit") {
                if store.perform({ try store.kits.setArchived(kit.id, !kit.isArchived) }) {
                    store.showToast(kit.isArchived ? "Kit restored" : "Kit archived")
                }
            }
            .buttonStyle(CKSecondaryButtonStyle())
            Button("Delete Kit") { confirmDelete = true }
                .buttonStyle(CKDestructiveButtonStyle())
        }
        .navigationTitle(kit.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            KitEditorView(kitID: kit.id).environmentObject(store)
        }
        .confirmationDialog("Delete \(kit.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Kit", role: .destructive) {
                if store.perform({ try store.kits.delete(kit.id) }) {
                    store.showToast("Kit deleted")
                    dismiss()
                }
            }
        } message: {
            Text("The template and any saved preparation are removed. Past handovers keep their own record of what was taken.")
        }
    }

    private func kitLineRow(_ line: KitLine) -> some View {
        let tool = store.workshop.tool(line.toolID)
        let issue = KitRules.issue(for: line, in: store.workshop)
        let available = store.balance(line.toolID).available
        return HStack(spacing: CK.Space.s) {
            ToolThumbnail(tool: tool, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool?.name ?? line.toolNameSnapshot).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                if let issue {
                    TagView(text: issue.text, icon: "exclamationmark.triangle", color: CK.Palette.needsService)
                } else {
                    Text("\(available) Available now")
                        .font(CKFont.footnote)
                        .foregroundColor(available >= line.requiredQuantity ? CK.Palette.inkSecondary : CK.Palette.needsService)
                }
            }
            Spacer()
            Text("× \(line.requiredQuantity)")
                .font(CKFont.smallFigure)
                .foregroundColor(CK.Palette.ink)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Create or edit a kit template: name, purpose, tools with quantities, order.
struct KitEditorView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let kitID: UUID?
    var initialTools: [UUID] = []
    var onSaved: ((KitTemplate) -> Void)?

    @State private var draft = KitDraft()
    @State private var error: String?
    @State private var picking = false
    @State private var loaded = false
    @State private var notice: String?
    @State private var highlighted: UUID?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                CKScroll {
                    if let error { NoticeView(text: error, tone: .error).id("error") }
                    CKTextField(label: "Kit Name", text: $draft.name, placeholder: "Deck Repair", required: true,
                                limit: Limits.nameLength.upperBound, capitalization: .words)
                    CKTextArea(label: "Purpose", text: $draft.purpose, limit: Limits.purposeMax, minHeight: 64)

                    CKSectionHeader(title: "Tools") {
                        Text("\(draft.lines.count)/\(Limits.kitLines.upperBound)")
                            .font(CKFont.footnote.monospacedDigit())
                            .foregroundColor(CK.Palette.inkSecondary)
                    }
                    if let notice { NoticeView(text: notice, tone: .info) }
                    if draft.lines.isEmpty {
                        Text("Add the tools this job needs, with how many of each.")
                            .font(CKFont.subhead)
                            .foregroundColor(CK.Palette.inkSecondary)
                    }
                    ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                        lineEditor(index: index, line: line).id(line.id)
                    }
                    Button { picking = true } label: { Label("Add Tool", systemImage: "plus") }
                        .buttonStyle(CKSecondaryButtonStyle())
                        .disabled(draft.lines.count >= Limits.kitLines.upperBound)

                    CKTextArea(label: "Preparation Note", text: $draft.preparationNote, limit: Limits.notesMax, minHeight: 64,
                               helper: "Anything to check before the job — charge batteries, pack spare bits.")
                }
                .onChange(of: error) { value in if value != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } } }
                .onChange(of: highlighted) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .navigationTitle(kitID == nil ? "New Kit" : "Edit Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(CKFont.button) }
            }
            .sheet(isPresented: $picking) {
                ToolPickerSheet(title: "Add Tool", excluded: []) { tool in add(tool) }
                    .environmentObject(store)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let kitID, let kit = store.workshop.kit(kitID) {
                draft = KitDraft(kit: kit)
            } else {
                draft.lines = initialTools.map { .init(toolID: $0, requiredQuantity: 1) }
            }
        }
    }

    private func lineEditor(index: Int, line: KitDraft.Line) -> some View {
        let tool = store.workshop.tool(line.toolID)
        let issue: KitLineIssue? = tool == nil ? .missingTool : (tool!.isArchived ? .archivedTool : nil)
        return VStack(alignment: .leading, spacing: CK.Space.xs) {
            HStack(spacing: CK.Space.s) {
                ToolThumbnail(tool: tool, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool?.name ?? "Removed Tool").font(CKFont.headline).foregroundColor(CK.Palette.ink)
                    if let issue {
                        TagView(text: issue.text, icon: "exclamationmark.triangle", color: CK.Palette.needsService)
                    }
                }
                Spacer()
                Menu {
                    Button { move(index, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                        .disabled(index == 0)
                    Button { move(index, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                        .disabled(index == draft.lines.count - 1)
                    Button(role: .destructive) { draft.lines.remove(at: index) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundColor(CK.Palette.velvet)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Line options for \(tool?.name ?? "removed tool")")
            }
            HStack {
                CKLabel("required quantity")
                Spacer()
                QuantityStepper(value: $draft.lines[index].requiredQuantity, range: Limits.quantity,
                                label: "Required Quantity", compact: true)
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card)
            .strokeBorder(highlighted == line.id ? CK.Palette.gold : CK.Palette.hairline, lineWidth: highlighted == line.id ? 2 : 1))
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.lines.indices.contains(target) else { return }
        draft.lines.swapAt(index, target)
    }

    /// A tool already in the kit is not added twice — its line is highlighted so the
    /// quantity can be changed instead.
    private func add(_ tool: Tool) {
        if let existing = draft.lines.first(where: { $0.toolID == tool.id }) {
            notice = "\(tool.name) is already in this kit (× \(existing.requiredQuantity)). Change its quantity below."
            highlighted = existing.id
        } else {
            let line = KitDraft.Line(toolID: tool.id, requiredQuantity: 1)
            draft.lines.append(line)
            notice = nil
            highlighted = line.id
        }
    }

    private func save() {
        do {
            let kit = try store.kits.save(draft, id: kitID)
            store.showToast(kitID == nil ? "\(kit.name) created" : "Kit saved")
            dismiss()
            onSaved?(kit)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Searchable list of active tools with their availability. Archived tools are never offered.
struct ToolPickerSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let excluded: Set<UUID>
    var availableOnly = false
    let onPick: (Tool) -> Void

    @State private var search = ""

    var body: some View {
        let query = search.trimmed
        let tools = store.activeTools
            .filter { !excluded.contains($0.id) }
            .filter { !availableOnly || store.balance($0.id).available > 0 }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.ownLabel.localizedCaseInsensitiveContains(query) }
        NavigationView {
            CKScroll(spacing: CK.Space.s) {
                if tools.isEmpty {
                    Text(availableOnly ? "No other tools have Available units." : "No tools match.")
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CK.Space.l)
                }
                ForEach(tools) { tool in
                    Button {
                        onPick(tool)
                        dismiss()
                    } label: {
                        ToolRow(tool: tool, balance: store.balance(tool.id),
                                locationName: store.workshop.location(tool.homeLocationID)?.name ?? "")
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or Own Label")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
