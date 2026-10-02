import SwiftUI

/// Holds the Tool Editor's draft and the photos added or removed while it is open, so
/// Cancel can put the disk back the way it was.
@MainActor
final class ToolEditorModel: ObservableObject {
    enum Mode: Equatable {
        case create
        case edit(UUID)
    }

    @Published var draft: ToolDraft
    @Published var mode: Mode
    @Published var error: String?
    @Published var hasPurchaseDate: Bool

    private(set) var trackingLocked = false
    private(set) var currentTotal = 0
    private var addedPhotoIDs: [String] = []
    private var removedPhotoIDs: [String] = []

    init(mode: Mode, store: WorkshopStore) {
        self.mode = mode
        let currency = store.workshop.settings.defaultCurrencyCode
        switch mode {
        case .create:
            var draft = ToolDraft(currencyCode: currency)
            if store.workshop.locations.count == 1 { draft.homeLocationID = store.workshop.locations[0].id }
            self.draft = draft
            hasPurchaseDate = false
        case .edit(let id):
            if let tool = store.workshop.tool(id) {
                draft = ToolDraft(tool: tool, fallbackCurrency: currency)
                hasPurchaseDate = tool.purchaseDate != nil
                trackingLocked = StockLedger.hasMovements(toolID: id, in: store.workshop)
                currentTotal = store.balance(id).total
            } else {
                draft = ToolDraft(currencyCode: currency)
                hasPurchaseDate = false
            }
        }
    }

    var isCreating: Bool { mode == .create }

    func addPhotos(_ data: [Data], store: WorkshopStore) {
        for item in data {
            guard draft.photoIDs.count < Limits.photosMax else { break }
            do {
                let id = try store.photos.save(item)
                draft.photoIDs.append(id)
                addedPhotoIDs.append(id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func removePhoto(_ id: String) {
        // The file stays until Save (then removed photos go) or Cancel (then everything
        // added in this session goes), so either way nothing is orphaned or lost early.
        draft.photoIDs.removeAll { $0 == id }
        removedPhotoIDs.append(id)
    }

    func movePhotoFirst(_ id: String) {
        guard let index = draft.photoIDs.firstIndex(of: id) else { return }
        draft.photoIDs.insert(draft.photoIDs.remove(at: index), at: 0)
    }

    /// Duplicate Description: keep the shared description, start a new record.
    func duplicateDescription(store: WorkshopStore) {
        // Unsaved photo additions belonged to the original's edit; they are not carried over.
        store.photos.delete(addedPhotoIDs)
        draft = draft.duplicatedDescription()
        mode = .create
        trackingLocked = false
        hasPurchaseDate = false
        addedPhotoIDs = []
        removedPhotoIDs = []
        error = nil
    }

    func save(store: WorkshopStore) -> Tool? {
        var draft = draft
        if !hasPurchaseDate { draft.purchaseDate = nil }
        do {
            let tool: Tool
            switch mode {
            case .create: tool = try store.tools.create(draft)
            case .edit(let id): tool = try store.tools.update(id, with: draft)
            }
            store.photos.delete(removedPhotoIDs)
            addedPhotoIDs = []
            removedPhotoIDs = []
            return tool
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func cancel(store: WorkshopStore) {
        store.photos.delete(addedPhotoIDs)
        addedPhotoIDs = []
    }
}

struct ToolEditorView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss

    let initialMode: ToolEditorModel.Mode
    var onSaved: ((Tool) -> Void)?

    init(mode: ToolEditorModel.Mode, onSaved: ((Tool) -> Void)? = nil) {
        initialMode = mode
        self.onSaved = onSaved
    }

    var body: some View {
        ToolEditorForm(model: ToolEditorModel(mode: initialMode, store: store), onSaved: onSaved)
    }
}

private struct ToolEditorForm: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    @StateObject var model: ToolEditorModel
    var onSaved: ((Tool) -> Void)?

    private enum ActiveSheet: Identifiable {
        case library, camera, newLocation
        var id: Int { hashValue }
    }

    @State private var sheet: ActiveSheet?
    @State private var cameraDenied = false

    init(model: ToolEditorModel, onSaved: ((Tool) -> Void)?) {
        _model = StateObject(wrappedValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                CKScroll {
                    if let error = model.error {
                        NoticeView(text: error, tone: .error).id("error")
                    }
                    photosSection
                    basicsSection
                    quantitySection
                    locationSection
                    identitySection
                    purchaseSection
                    CKTextArea(label: "Notes", text: $model.draft.notes, limit: Limits.notesMax)
                    if !model.isCreating {
                        Button {
                            model.duplicateDescription(store: store)
                            proxy.scrollTo("top", anchor: .top)
                        } label: {
                            Label("Duplicate Description", systemImage: "plus.square.on.square")
                        }
                        .buttonStyle(CKSecondaryButtonStyle())
                        Text("Starts a new record with the same description — for another tool with its own serial number.")
                            .font(CKFont.caption)
                            .foregroundColor(CK.Palette.inkSecondary)
                    }
                }
                .onChange(of: model.error) { error in
                    if error != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } }
                }
            }
            .navigationTitle(model.isCreating ? "New Tool" : "Edit Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel(store: store)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(CKFont.button)
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: $sheet) { item in
            switch item {
            case .library:
                PhotoLibraryPicker(limit: Limits.photosMax - model.draft.photoIDs.count) { data in
                    model.addPhotos(data, store: store)
                }
                .ignoresSafeArea()
            case .camera:
                CameraPicker { data in model.addPhotos([data], store: store) }
                    .ignoresSafeArea()
            case .newLocation:
                LocationEditorView(locationID: nil) { location in
                    model.draft.homeLocationID = location.id
                }
                .environmentObject(store)
            }
        }
        .alert("Camera Access Is Off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Choose from Library") { sheet = .library }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to photograph your tools, or choose a photo from your library.")
        }
    }

    private func save() {
        if let tool = model.save(store: store) {
            store.showToast(model.isCreating ? "\(tool.name) added" : "Changes saved")
            dismiss()
            onSaved?(tool)
        }
    }

    // MARK: - Sections

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.xs) {
            FieldLabel(label: "Photos", required: false).id("top")
            if model.draft.photoIDs.isEmpty {
                HStack(spacing: CK.Space.s) {
                    Sprite("ck06_tool_tag", size: CGSize(width: 64, height: 80))
                    Text("Your own photos make the right tool easy to spot. Up to \(Limits.photosMax).")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CK.Space.xs) {
                        ForEach(Array(model.draft.photoIDs.enumerated()), id: \.element) { index, id in
                            PhotoTile(id: id, isCover: index == 0) {
                                model.removePhoto(id)
                            } makeCover: {
                                model.movePhotoFirst(id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if model.draft.photoIDs.count < Limits.photosMax {
                Menu {
                    Button { sheet = .library } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
                    if CameraPicker.isAvailable {
                        Button {
                            if CameraPicker.isDenied { cameraDenied = true } else { sheet = .camera }
                        } label: { Label("Take Photo", systemImage: "camera") }
                    }
                } label: {
                    Label("Add Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CKSecondaryButtonStyle())
            } else {
                Text("\(Limits.photosMax) of \(Limits.photosMax) photos. Remove one to add another.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
        }
    }

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.m) {
            CKTextField(label: "Name", text: $model.draft.name, placeholder: "Cordless Drill", required: true,
                        limit: Limits.nameLength.upperBound, capitalization: .words)
            CKMenuField(label: "Category", selection: $model.draft.category, options: ToolCategory.allCases,
                        title: { $0.title }, required: true)
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(label: "Tracking Mode", required: true)
                CKSegmented(selection: $model.draft.trackingMode, options: TrackingMode.allCases) { $0.title }
                    .disabled(model.trackingLocked)
                Text(model.trackingLocked
                     ? "Tracking Mode can't change after the first checkout, service or stock change. Create a new record instead."
                     : model.draft.trackingMode.explanation)
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isCreating {
                FieldLabel(label: "Initial Quantity", required: true)
                if model.draft.trackingMode == .individual {
                    Text("1 unit — an individual tool is always one unit.")
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.ink)
                        .padding(.horizontal, CK.Space.s)
                        .frame(maxWidth: .infinity, minHeight: CK.Size.field, alignment: .leading)
                        .background(FieldBackground())
                } else {
                    QuantityStepper(value: $model.draft.initialQuantity, range: Limits.quantity, label: "Initial Quantity")
                }
            } else {
                FieldLabel(label: "Quantity", required: false)
                Text("\(Format.units(model.currentTotal)) recorded. Change it with Adjust Stock on the tool page, so every change keeps its reason and time.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: "Home Location", required: true)
            if store.workshop.locations.isEmpty {
                Text("No storage locations yet. Create one to give this tool a place.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Menu {
                    Picker("Home Location", selection: Binding(
                        get: { model.draft.homeLocationID },
                        set: { model.draft.homeLocationID = $0 }
                    )) {
                        ForEach(store.sortedLocations) { location in
                            Text(location.name).tag(Optional(location.id))
                        }
                    }
                } label: {
                    HStack {
                        Text(model.draft.homeLocationID.flatMap { store.workshop.location($0)?.name } ?? "Choose a location")
                            .font(CKFont.body)
                            .foregroundColor(model.draft.homeLocationID == nil ? CK.Palette.inkSecondary : CK.Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(CKFont.footnote.weight(.semibold))
                            .foregroundColor(CK.Palette.copper)
                    }
                    .padding(.horizontal, CK.Space.s)
                    .frame(minHeight: CK.Size.field)
                    .background(FieldBackground())
                }
                .accessibilityLabel("Home Location, required")
            }
            Button {
                sheet = .newLocation
            } label: {
                Label("Create Location", systemImage: "plus")
            }
            .buttonStyle(CKTextButtonStyle())
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: CK.Space.m) {
            CKTextField(label: "Own Label", text: $model.draft.ownLabel, placeholder: "e.g. D-02, blue tape",
                        helper: "Optional. Whatever you've written or stuck on it.", limit: Limits.labelMax)
            CKTextField(label: "Serial Number", text: $model.draft.serialNumber, placeholder: "Optional",
                        helper: model.draft.trackingMode == .identicalUnits
                            ? "Identical units share one description. Tools with different serial numbers need separate records."
                            : nil,
                        limit: Limits.serialMax, capitalization: .characters)
        }
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.hasPurchaseDate) {
                    FieldLabel(label: "Purchase Date", required: false)
                }
                .tint(CK.Palette.copper)
                if model.hasPurchaseDate {
                    DatePicker("Purchase Date", selection: Binding(
                        get: { model.draft.purchaseDate ?? Date() },
                        set: { model.draft.purchaseDate = $0 }
                    ), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(CKFont.body)
                    .onAppear { if model.draft.purchaseDate == nil { model.draft.purchaseDate = Date() } }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(label: "Private Purchase Cost", required: false)
                HStack(spacing: CK.Space.xs) {
                    TextField(model.draft.cost.zeroConfirmed ? "0 — recorded as zero" : "Unknown", text: Binding(
                        get: { model.draft.cost.amountText },
                        set: { value in
                            model.draft.cost.amountText = value
                            if !value.trimmed.isEmpty { model.draft.cost.zeroConfirmed = false }
                        }
                    ))
                    .font(CKFont.body.monospacedDigit())
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, CK.Space.s)
                    .frame(minHeight: CK.Size.field)
                    .background(FieldBackground())
                    .accessibilityLabel("Purchase cost amount")

                    Menu {
                        Picker("Currency", selection: $model.draft.cost.currencyCode) {
                            ForEach(Currencies.all(including: model.draft.cost.currencyCode), id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.draft.cost.currencyCode)
                                .font(CKFont.body.weight(.semibold))
                                .foregroundColor(CK.Palette.ink)
                            Image(systemName: "chevron.down")
                                .font(CKFont.caption.weight(.bold))
                                .foregroundColor(CK.Palette.copper)
                        }
                        .padding(.horizontal, CK.Space.s)
                        .frame(minWidth: 84, minHeight: CK.Size.field)
                        .background(FieldBackground())
                    }
                    .accessibilityLabel("Currency: \(model.draft.cost.currencyCode)")
                }
                HStack {
                    if model.draft.cost.zeroConfirmed {
                        TagView(text: "Recorded as zero", icon: "checkmark", color: CK.Palette.velvet)
                        Button("Clear") { model.draft.cost.zeroConfirmed = false }
                            .buttonStyle(CKTextButtonStyle())
                    } else {
                        Button("Enter Zero") {
                            model.draft.cost.amountText = ""
                            model.draft.cost.zeroConfirmed = true
                        }
                        .buttonStyle(CKTextButtonStyle())
                        .accessibilityHint("Records that this tool cost nothing, for example a gift")
                    }
                    Spacer()
                }
                Text("Private and optional: what you paid for the whole batch on the purchase date — not a unit price or today's value. Leave it empty if you don't know.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PhotoTile: View {
    @EnvironmentObject private var store: WorkshopStore
    let id: String
    let isCover: Bool
    let remove: () -> Void
    let makeCover: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = store.photos.load(id), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    CK.Palette.surfaceSunken
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: CK.Radius.thumb, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if isCover {
                    Text("Cover")
                        .font(CKFont.caption.weight(.semibold))
                        .foregroundColor(CK.Palette.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(CK.Palette.gold))
                        .padding(4)
                }
            }
            .contextMenu {
                if !isCover { Button("Use as Cover", action: makeCover) }
                Button("Remove Photo", role: .destructive, action: remove)
            }

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(CK.Palette.cream, CK.Palette.deepBlue)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .offset(x: 10, y: -10)
            .accessibilityLabel("Remove photo")
        }
        .padding(.trailing, 6)
        .accessibilityElement(children: .contain)
    }
}
