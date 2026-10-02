import SwiftUI

/// Storage tab: the places tools live, with what is physically there now.
struct StorageListView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter
    @State private var creating = false

    var body: some View {
        CKScroll(spacing: CK.Space.s) {
            if store.workshop.locations.isEmpty {
                EmptyStateView(asset: "ck07_blue_tray", assetSize: CGSize(width: 104, height: 88),
                               title: "Add a Storage Location",
                               message: "A shelf, a drawer, a case in the garage — somewhere each tool comes home to.") {
                    Button { creating = true } label: { Label("Create Location", systemImage: "plus") }
                        .buttonStyle(CKPrimaryButtonStyle())
                }
                .padding(.top, CK.Space.xl)
            } else {
                ForEach(store.sortedLocations) { location in
                    NavigationLink(destination: LocationDetailView(locationID: location.id)) {
                        LocationRow(location: location)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(destination: InventoryCheckView(locationID: nil)) {
                    Label("Inventory Check · All Locations", systemImage: "checklist")
                }
                .buttonStyle(CKSecondaryButtonStyle())
                .padding(.top, CK.Space.xs)
            }
        }
        .navigationTitle("Storage")
        .toolbar {
            HomeToolbarItem(router: router)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { creating = true } label: {
                    Label("Create", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(CKFont.subhead.weight(.semibold))
                }
                .accessibilityLabel("Create Location")
            }
        }
        .background(RouteLink(route: $router.locationRoute) { LocationDetailView(locationID: $0) })
        .sheet(isPresented: $creating) {
            LocationEditorView(locationID: nil).environmentObject(store)
        }
    }
}

private struct LocationRow: View {
    @EnvironmentObject private var store: WorkshopStore
    let location: StorageLocation

    var body: some View {
        let tools = store.workshop.tools.filter { $0.homeLocationID == location.id }
        let atHome = tools.reduce(0) { $0 + store.balance($1.id).atHome }
        let service = tools.reduce(0) { $0 + store.balance($1.id).needsService }
        return HStack(spacing: CK.Space.s) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CK.Palette.gold)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: CK.Radius.thumb).fill(CK.Palette.velvet))
            VStack(alignment: .leading, spacing: 3) {
                Text(location.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                let detail = [location.roomZone.nilIfBlank, location.shelfLabel.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("\(tools.count) \(tools.count == 1 ? "tool" : "tools")")
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                    if service > 0 { StatusBadge(.needsService, count: service) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(atHome)").font(CKFont.rowFigure).foregroundColor(CK.Palette.ink)
                CKLabel("at home")
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).strokeBorder(CK.Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(location.name), \(tools.count) tools, \(atHome) units at home\(service > 0 ? ", \(service) need service" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// One location: its tools, what is ready and what is set aside, and inventory.
struct LocationDetailView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let locationID: UUID

    private enum Show: String, CaseIterable { case all = "All", ready = "Ready", service = "Needs Service" }

    @State private var show: Show = .all
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var editing = false
    @State private var moving = false
    @State private var deleting = false
    @State private var confirmDeleteEmpty = false

    var body: some View {
        if let location = store.workshop.location(locationID) {
            content(location)
        } else {
            EmptyStateView(asset: nil, title: "Location Removed", message: DomainError.locationMissing.message)
                .background(CK.Palette.background.ignoresSafeArea())
        }
    }

    private func content(_ location: StorageLocation) -> some View {
        let assigned = store.workshop.tools.filter { $0.homeLocationID == location.id }.sorted(by: WorkshopStore.byName)
        let ready = assigned.reduce(0) { $0 + store.balance($1.id).available }
        let service = assigned.reduce(0) { $0 + store.balance($1.id).needsService }
        let visible = assigned.filter { tool in
            let balance = store.balance(tool.id)
            switch show {
            case .all: return true
            case .ready: return balance.available > 0
            case .service: return balance.needsService > 0
            }
        }

        return CKScroll {
            HStack(alignment: .center, spacing: CK.Space.m) {
                Sprite("ck07_blue_tray", size: CGSize(width: 104, height: 88))
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.name).font(CKFont.title).foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !location.roomZone.isEmpty { KeyValueRow(key: "room/zone", value: location.roomZone) }
                    if !location.shelfLabel.isEmpty { KeyValueRow(key: "shelf/box", value: location.shelfLabel) }
                }
            }
            if !location.notes.isEmpty {
                Text(location.notes).font(CKFont.subhead).foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CKCard {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(ready + service)").ckFigure(40).foregroundColor(CK.Palette.ink)
                    CKLabel("at home units")
                    Spacer()
                }
                HStack(spacing: CK.Space.xs) {
                    StatusBadge(.available, count: ready)
                    StatusBadge(.needsService, count: service)
                }
                Text("At Home = Available + Needs Service. Units that are out are counted with their handover, not here. Needs Service here means set aside at home.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: CK.Space.s) {
                NavigationLink(destination: InventoryCheckView(locationID: location.id)) {
                    Label("Start Inventory", systemImage: "checklist")
                }
                .buttonStyle(CKPrimaryButtonStyle())
                .disabled(assigned.isEmpty)
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(CKSecondaryButtonStyle())
            }

            CKSectionHeader(title: "Tools Here") {
                if !assigned.isEmpty {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selection.removeAll()
                    }
                    .buttonStyle(CKTextButtonStyle())
                }
            }
            if !assigned.isEmpty {
                CKSegmented(selection: $show, options: Show.allCases) { $0.rawValue }
            }
            if assigned.isEmpty {
                Text("No tools call this place home yet.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
            } else if visible.isEmpty {
                Text(show == .ready ? "Nothing ready here right now." : "Nothing set aside for service here.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            ForEach(visible) { tool in
                if selecting {
                    Button {
                        if selection.contains(tool.id) { selection.remove(tool.id) } else { selection.insert(tool.id) }
                    } label: {
                        HStack(spacing: CK.Space.xs) {
                            Image(systemName: selection.contains(tool.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selection.contains(tool.id) ? CK.Palette.copper : CK.Palette.inkSecondary)
                            ToolRow(tool: tool, balance: store.balance(tool.id), locationName: location.name)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selection.contains(tool.id) ? "Selected" : "Not selected")
                } else {
                    NavigationLink(destination: ToolDetailView(toolID: tool.id)) {
                        ToolRow(tool: tool, balance: store.balance(tool.id), locationName: location.name)
                    }
                    .buttonStyle(.plain)
                }
            }
            if selecting {
                Button("Move Selected Tools (\(selection.count))") { moving = true }
                    .buttonStyle(CKPrimaryButtonStyle())
                    .disabled(selection.isEmpty)
            }

            CKSectionHeader("Manage")
            Button("Delete Location") {
                if assigned.isEmpty { confirmDeleteEmpty = true } else { deleting = true }
            }
            .buttonStyle(CKDestructiveButtonStyle())
            if !assigned.isEmpty {
                Text("\(assigned.count) \(assigned.count == 1 ? "tool" : "tools") (archived included) will need a new Home Location first.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            LocationEditorView(locationID: location.id).environmentObject(store)
        }
        .sheet(isPresented: $moving) {
            MoveToolsSheet(toolIDs: Array(selection)) {
                selection.removeAll()
                selecting = false
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $deleting) {
            DeleteLocationSheet(location: location) { dismiss() }.environmentObject(store)
        }
        .confirmationDialog("Delete \(location.name)?", isPresented: $confirmDeleteEmpty, titleVisibility: .visible) {
            Button("Delete Location", role: .destructive) {
                if store.perform("Can't Delete", { try store.locations.delete(location.id, reassignTo: nil) }) {
                    store.showToast("Location deleted")
                    dismiss()
                }
            }
        } message: {
            Text("No tools use this location.")
        }
    }
}

/// Deleting a location that still has tools: pick one new home for all of them.
private struct DeleteLocationSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let location: StorageLocation
    let onDeleted: () -> Void

    @State private var target: UUID?
    @State private var error: String?

    var body: some View {
        let others = store.sortedLocations.filter { $0.id != location.id }
        let count = store.workshop.tools.filter { $0.homeLocationID == location.id }.count
        NavigationView {
            CKScroll(spacing: CK.Space.s) {
                if let error { NoticeView(text: error, tone: .error) }
                Text("\(count) \(count == 1 ? "tool uses" : "tools use") \(location.name), including archived ones. Choose where they live now; then the location is deleted.")
                    .font(CKFont.body)
                    .foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if others.isEmpty {
                    NoticeView(text: "Create another location first — there's nowhere else to move these tools.", tone: .warning)
                }
                ForEach(others) { other in
                    Button { target = other.id } label: {
                        HStack {
                            Image(systemName: target == other.id ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(target == other.id ? CK.Palette.copper : CK.Palette.inkSecondary)
                            Text(other.name).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                            Spacer()
                        }
                        .padding(CK.Space.s)
                        .frame(minHeight: CK.Size.button)
                        .background(RoundedRectangle(cornerRadius: CK.Radius.control).fill(CK.Palette.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(target == other.id ? [.isSelected] : [])
                }
                Button("Move Tools and Delete") {
                    do {
                        try store.locations.delete(location.id, reassignTo: target)
                        store.showToast("Location deleted")
                        dismiss()
                        onDeleted()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(CKDestructiveButtonStyle())
                .disabled(target == nil)
                .padding(.top, CK.Space.s)
            }
            .navigationTitle("Delete Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Create or edit a storage location.
struct LocationEditorView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let locationID: UUID?
    var onSaved: ((StorageLocation) -> Void)?

    @State private var draft = LocationDraft()
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                CKTextField(label: "Location Name", text: $draft.name, placeholder: "Garage Shelf A", required: true,
                            limit: Limits.nameLength.upperBound, capitalization: .words)
                CKTextField(label: "Room/Zone", text: $draft.roomZone, placeholder: "Garage", limit: Limits.nameLength.upperBound,
                            capitalization: .words)
                CKTextField(label: "Shelf/Box Label", text: $draft.shelfLabel, placeholder: "Top drawer", limit: Limits.nameLength.upperBound)
                CKTextArea(label: "Notes", text: $draft.notes, limit: Limits.notesMax, minHeight: 80)
                Text("Describe the place in your own words. Addresses aren't needed.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            .navigationTitle(locationID == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.font(CKFont.button)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = locationID, let location = store.workshop.location(id) { draft = LocationDraft(location: location) }
        }
    }

    private func save() {
        do {
            if let id = locationID {
                try store.locations.update(id, with: draft)
                if let location = store.workshop.location(id) { onSaved?(location) }
                store.showToast("Location saved")
            } else {
                let location = try store.locations.create(draft)
                onSaved?(location)
                store.showToast("\(location.name) created")
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
