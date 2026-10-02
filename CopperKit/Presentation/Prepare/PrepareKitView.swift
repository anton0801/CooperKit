import SwiftUI

/// Prepare Kit: tick things off against what is Available right now. Ticking never
/// moves stock and never reserves anything; availability is checked again at Confirm.
struct PrepareKitView: View {
    enum Source: Equatable {
        case kit(UUID)
        case repeatHandover(UUID)
    }

    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    let source: Source

    @State private var run: PreparationRun?
    @State private var dirty = false
    @State private var loadError: String?
    @State private var error: String?
    @State private var replacing: UUID?
    @State private var editingQuantity: UUID?
    @State private var reviewing = false
    @State private var confirmDiscard = false
    @State private var confirmTemplate = false

    var body: some View {
        Group {
            if let run {
                content(run)
            } else if let loadError {
                EmptyStateView(asset: nil, title: "Can't Prepare", message: loadError)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CK.Palette.background.ignoresSafeArea())
        .navigationTitle("Prepare Kit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard run == nil else { return }
        do {
            switch source {
            case .kit(let id): run = try store.preparation.run(forKit: id)
            case .repeatHandover(let id): run = try store.preparation.repeatRun(ofHandover: id)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private var isSaved: Bool {
        guard let run else { return false }
        return store.workshop.preparations.contains { $0.id == run.id }
    }

    private func content(_ run: PreparationRun) -> some View {
        let evaluation = PreparationRules.evaluate(run, in: store.workshop, balances: store.balances)
        return ScrollViewReader { proxy in
            CKScroll {
                header(run, evaluation)
                if let error { NoticeView(text: error, tone: .error).id("error") }

                ForEach(evaluation.lines) { item in
                    lineCard(item)
                }

                CKTextArea(label: "Run Note", text: Binding(
                    get: { self.run?.runNote ?? "" },
                    set: { self.run?.runNote = $0; dirty = true }
                ), limit: Limits.notesMax, minHeight: 64, helper: "For this run only — the template is not changed.")

                footer(run, evaluation)
            }
            .onChange(of: error) { value in if value != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } } }
        }
        .sheet(isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            ToolPickerSheet(title: "Replace Tool",
                            excluded: Set(run.activeLines.map(\.toolID))) { tool in
                if let lineID = replacing { mutate { try $0.replace(lineID, with: tool) } }
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $reviewing) {
            CheckoutReviewView(source: .preparation(run, summary: PreparationRules.summary(run, evaluation: evaluation, kitName: kitName(run)))) { handover in
                dismiss()
                router.openHandover(handover.id)
            }
            .environmentObject(store)
        }
        .confirmationDialog("Discard this preparation?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                if isSaved { store.perform { try store.preparation.discard(run.id) } }
                dismiss()
            }
        } message: {
            Text("Marks, replacements and quantities for this run are cleared. The template stays as it is.")
        }
        .confirmationDialog("Update the template?", isPresented: $confirmTemplate, titleVisibility: .visible) {
            Button("Update Template") {
                if store.perform({ try store.preparation.updateTemplate(from: run) }) {
                    store.showToast("Template updated")
                }
            }
        } message: {
            Text("The kit template will list this run's tools and quantities from now on.")
        }
    }

    // MARK: - Pieces

    private func header(_ run: PreparationRun, _ evaluation: PrepEvaluation) -> some View {
        VStack(alignment: .leading, spacing: CK.Space.s) {
            HStack(alignment: .center, spacing: CK.Space.m) {
                Sprite("ck09_glove_clipboard", size: CGSize(width: 80, height: 88))
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title)
                        .font(CKFont.title)
                        .foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(evaluation.preparedCount) of \(evaluation.activeLines.count) prepared")
                        .font(CKFont.headline.monospacedDigit())
                        .foregroundColor(CK.Palette.copper)
                    if dirty {
                        TagView(text: "Not saved", icon: "circle.dashed", color: CK.Palette.inkSecondary)
                    } else if isSaved {
                        TagView(text: "Preparation saved", icon: "bookmark.fill", color: CK.Palette.velvet)
                    }
                }
            }
            Text("Preparing doesn't reserve anything. Availability is checked again when you confirm the checkout.")
                .font(CKFont.caption)
                .foregroundColor(CK.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let kitID = run.kitID, let kit = store.workshop.kit(kitID), !kit.preparationNote.isEmpty {
                NoticeView(text: kit.preparationNote, tone: .info)
            }
        }
    }

    private func lineCard(_ item: PrepLineEvaluation) -> some View {
        let line = item.line
        let removed = item.state == .removed
        return VStack(alignment: .leading, spacing: CK.Space.xs) {
            HStack(alignment: .center, spacing: CK.Space.xs) {
                if !removed {
                    CheckBox(isOn: Binding(
                        get: { line.isPrepared },
                        set: { value in mutate { $0.setPrepared(line.id, value) } }
                    ), label: "Prepared: \(line.toolNameSnapshot)")
                    .disabled(item.state.blocksCheckout && !line.isPrepared)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.tool?.name ?? line.toolNameSnapshot)
                        .font(CKFont.headline)
                        .foregroundColor(removed ? CK.Palette.inkSecondary : CK.Palette.ink)
                        .strikethrough(removed)
                    if line.isReplacement, let original = line.templateToolID {
                        Text("Replaces \(store.workshop.toolName(original)) for this run")
                            .font(CKFont.caption)
                            .foregroundColor(CK.Palette.copper)
                    }
                }
                Spacer(minLength: 4)
                stateBadge(item.state)
            }

            if !removed {
                HStack(spacing: CK.Space.m) {
                    let required = line.templateToolID == nil ? line.runQuantity : line.requiredQuantity
                    figure("required", required)
                    if line.runQuantity != required {
                        figure("this run", line.runQuantity, color: CK.Palette.copper)
                    }
                    figure("available now", item.availableNow)
                    if case .short(let missing) = item.state {
                        figure("missing", missing, color: CK.Palette.overdue)
                    }
                }

                if editingQuantity == line.id {
                    HStack {
                        CKLabel("quantity for this run")
                        Spacer()
                        QuantityStepper(value: Binding(
                            get: { line.runQuantity },
                            set: { value in mutate { try $0.setQuantity(line.id, value) } }
                        ), range: Limits.quantity, label: "Quantity for this run", compact: true)
                        Button("Done") { editingQuantity = nil }.buttonStyle(CKTextButtonStyle())
                    }
                }
            }

            HStack(spacing: CK.Space.xs) {
                if removed {
                    Button("Restore for This Run") { mutate { try $0.setRemoved(line.id, false) } }
                        .buttonStyle(CKTextButtonStyle())
                } else {
                    Menu {
                        Button { replacing = line.id } label: { Label("Replace Tool", systemImage: "arrow.triangle.2.circlepath") }
                        Button { editingQuantity = line.id } label: { Label("Change Quantity for This Run", systemImage: "minus.forwardslash.plus") }
                        if item.availableNow > 0 && item.availableNow < line.runQuantity {
                            Button { mutate { try $0.setQuantity(line.id, item.availableNow) } } label: {
                                Label("Reduce to \(item.availableNow) for This Run", systemImage: "arrow.down.to.line")
                            }
                        }
                        Button(role: .destructive) { mutate { try $0.setRemoved(line.id, true) } } label: {
                            Label("Remove for This Run", systemImage: "minus.circle")
                        }
                    } label: {
                        Label("Fix or Change", systemImage: "slider.horizontal.3")
                            .font(CKFont.subhead.weight(.semibold))
                            .foregroundColor(CK.Palette.velvet)
                            .frame(minHeight: 44)
                    }
                }
                Spacer()
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
            .fill(removed ? CK.Palette.surfaceSunken : CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
            .strokeBorder(item.state.blocksCheckout ? CK.Palette.needsService.opacity(0.7) : CK.Palette.hairline,
                          lineWidth: item.state.blocksCheckout ? 1.5 : 1))
    }

    private func figure(_ label: String, _ value: Int, color: Color = CK.Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(CKFont.smallFigure).foregroundColor(color)
            CKLabel(label)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stateBadge(_ state: PrepLineState) -> some View {
        switch state {
        case .ready:
            StatusBadge(title: "Ready", icon: "checkmark.circle.fill", fill: CK.Palette.available)
        case .notPrepared:
            TagView(text: "Not Prepared", icon: "circle", color: CK.Palette.inkSecondary)
        case .short:
            StatusBadge(title: "Short", icon: "minus.circle.fill", fill: CK.Palette.overdue)
        case .needsReview(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(title: "Needs Review", icon: "exclamationmark.triangle.fill", fill: CK.Palette.needsService)
                Text(reason)
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.needsService)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        case .removed:
            TagView(text: "Removed for This Run", color: CK.Palette.inkSecondary)
        }
    }

    private func footer(_ run: PreparationRun, _ evaluation: PrepEvaluation) -> some View {
        VStack(spacing: CK.Space.s) {
            if let reason = evaluation.blockingReason {
                NoticeView(text: reason, tone: .warning)
            } else if evaluation.preparedCount < evaluation.activeLines.count {
                NoticeView(text: "\(evaluation.activeLines.count - evaluation.preparedCount) not marked prepared. You can still review the checkout.", tone: .info)
            }
            Button { reviewing = true } label: { Label("Review Checkout", systemImage: "arrow.right.circle.fill") }
                .buttonStyle(CKPrimaryButtonStyle())
                .disabled(!evaluation.canCheckout)
            Button {
                do {
                    try store.preparation.save(run)
                    dirty = false
                    error = nil
                    store.showToast("Preparation saved")
                } catch {
                    self.error = error.localizedDescription
                }
            } label: { Label("Save Preparation", systemImage: "bookmark") }
                .buttonStyle(CKSecondaryButtonStyle())
            if run.kitID != nil && differsFromTemplate(run) {
                Button { confirmTemplate = true } label: { Label("Update Template", systemImage: "square.and.pencil") }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(evaluation.lines.contains { if case .needsReview = $0.state { return true }; return false })
            }
            Button("Discard") { confirmDiscard = true }
                .buttonStyle(CKTextButtonStyle(color: CK.Palette.overdue))
        }
        .padding(.top, CK.Space.xs)
    }

    // MARK: - Helpers

    private func mutate(_ change: (inout PreparationRun) throws -> Void) {
        guard var current = run else { return }
        do {
            try change(&current)
            run = current
            dirty = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func kitName(_ run: PreparationRun) -> String? {
        run.kitID.flatMap { store.workshop.kit($0)?.name }
    }

    private func differsFromTemplate(_ run: PreparationRun) -> Bool {
        guard let kitID = run.kitID, let kit = store.workshop.kit(kitID) else { return false }
        let runPairs = run.activeLines.map { "\($0.toolID)×\($0.runQuantity)" }
        let kitPairs = kit.lines.map { "\($0.toolID)×\($0.requiredQuantity)" }
        return runPairs != kitPairs
    }
}
