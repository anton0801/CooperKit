import SwiftUI

/// Checkout Review: the moment units actually leave Available. Everything before this
/// (preparation, ticks) was bookkeeping; Confirm moves every line or none of them.
struct CheckoutReviewView: View {
    enum Source: Equatable {
        case tool(UUID)
        case preparation(PreparationRun, summary: String)
    }

    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let source: Source
    var onCompleted: ((Handover) -> Void)?

    /// One key for the life of this screen: a second tap cannot hand out a second kit.
    @State private var operationID = UUID()
    @State private var mode: HandoverMode = .personalUse
    @State private var purpose = ""
    @State private var recipient = ""
    @State private var contactNote = ""
    @State private var startedAt = Date()
    @State private var dueAt = Date()
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var lines: [CheckoutRequest.Line] = []
    @State private var conditionNote = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var submitting = false
    @State private var addingTool = false
    @State private var pickingZone = false

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                CKScroll {
                    header
                    if let error { NoticeView(text: error, tone: .error).id("error") }
                    modeSection
                    datesSection
                    linesSection
                    CKTextArea(label: "Condition Out Note", text: $conditionNote, limit: Limits.conditionNoteMax, minHeight: 64,
                               helper: "How things looked when they left — scratches, battery charge, missing bits.")
                    summarySection
                    confirmSection
                }
                .onChange(of: error) { value in if value != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } } }
            }
            .navigationTitle("Checkout Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $addingTool) {
                ToolPickerSheet(title: "Add Tool", excluded: Set(lines.map(\.toolID)), availableOnly: true) { tool in
                    lines.append(.init(toolID: tool.id, quantity: 1))
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $pickingZone) {
                TimeZonePicker(selection: $timeZoneID)
            }
        }
        .interactiveDismissDisabled(submitting)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        startedAt = Date()
        dueAt = Calendar.current.date(byAdding: .day, value: store.workshop.settings.defaultLoanDays, to: startedAt) ?? startedAt
        switch source {
        case .tool(let id):
            lines = [.init(toolID: id, quantity: 1)]
        case .preparation(let run, _):
            lines = run.activeLines.map { .init(toolID: $0.toolID, quantity: $0.runQuantity) }
            purpose = String(run.title.prefix(Limits.checkoutPurpose.upperBound))
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: CK.Space.m) {
            Sprite("ck10_handover_case", size: CGSize(width: 96, height: 80))
            VStack(alignment: .leading, spacing: 4) {
                Text("Check what leaves the workshop")
                    .font(CKFont.headline)
                    .foregroundColor(CK.Palette.ink)
                Text("\(Format.units(lines.reduce(0) { $0 + $1.quantity })) in \(lines.count) \(lines.count == 1 ? "line" : "lines")")
                    .font(CKFont.subhead.monospacedDigit())
                    .foregroundColor(CK.Palette.inkSecondary)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(label: "Mode", required: true)
                CKSegmented(selection: $mode, options: HandoverMode.allCases) { $0.title }
                Text(mode == .loan
                     ? "Lent to someone else. It still has to come back to the workshop."
                     : "You're taking it yourself. It still has to come back to the workshop.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            CKTextField(label: "Purpose", text: $purpose, placeholder: "Fence repair at the cabin", required: true,
                        limit: Limits.checkoutPurpose.upperBound)
            if mode == .loan {
                CKTextField(label: "Recipient Name", text: $recipient, placeholder: "Who has it", required: true,
                            limit: Limits.recipientMax, capitalization: .words)
                CKTextField(label: "Contact Note", text: $contactNote, placeholder: "Optional — phone, flat number",
                            helper: "Typed by you. Copper Kit doesn't read your contacts or send messages.",
                            limit: Limits.contactNoteMax)
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.s) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(label: "Started At", required: true)
                DatePicker("Started At", selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Text("Can be earlier than now if you're recording a handover after the fact.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(label: "Due At", required: true)
                DatePicker("Due At", selection: $dueAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: timeZoneID) ?? .current)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CK.Space.xs) {
                        dueChip("+1 day", days: 1)
                        dueChip("+3 days", days: 3)
                        dueChip("+1 week", days: 7)
                        dueChip("+2 weeks", days: 14)
                    }
                }
                Button {
                    pickingZone = true
                } label: {
                    Label("Time Zone: \(zoneLabel)", systemImage: "globe")
                        .font(CKFont.subhead.weight(.semibold))
                }
                .buttonStyle(CKTextButtonStyle())
                if dueAt < Date() {
                    NoticeView(text: "This due date has already passed. The handover will be Overdue as soon as it's saved.", tone: .warning)
                }
            }
        }
    }

    private var zoneLabel: String {
        let zone = TimeZone(identifier: timeZoneID) ?? .current
        return "\(zone.identifier.replacingOccurrences(of: "_", with: " ")) (\(zone.abbreviation(for: dueAt) ?? ""))"
    }

    private func dueChip(_ title: String, days: Int) -> some View {
        Button(title) {
            dueAt = Calendar.current.date(byAdding: .day, value: days, to: startedAt) ?? dueAt
        }
        .font(CKFont.subhead.weight(.semibold))
        .foregroundColor(CK.Palette.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(CK.Palette.cream))
        .overlay(Capsule().strokeBorder(CK.Palette.copper.opacity(0.6), lineWidth: 1))
        .frame(minHeight: 44)
        .accessibilityLabel("Due \(title) from start")
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: CK.Space.s) {
            CKSectionHeader(title: "Selected Lines") {
                Button { addingTool = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(CKTextButtonStyle())
            }
            if lines.isEmpty {
                NoticeView(text: "Nothing selected. Add at least one tool — an empty checkout can't be confirmed.", tone: .warning)
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                lineRow(index: index, line: line)
            }
        }
    }

    private func lineRow(index: Int, line: CheckoutRequest.Line) -> some View {
        let tool = store.workshop.tool(line.toolID)
        let available = store.balance(line.toolID).available
        let over = line.quantity > available
        return VStack(alignment: .leading, spacing: CK.Space.xs) {
            HStack(spacing: CK.Space.s) {
                ToolThumbnail(tool: tool, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool?.name ?? "Removed Tool").font(CKFont.headline).foregroundColor(CK.Palette.ink)
                    Text("\(available) Available now")
                        .font(CKFont.footnote)
                        .foregroundColor(over ? CK.Palette.overdue : CK.Palette.inkSecondary)
                }
                Spacer()
                Button {
                    lines.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(CK.Palette.overdue)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove \(tool?.name ?? "line")")
            }
            HStack {
                CKLabel("quantity")
                Spacer()
                QuantityStepper(value: $lines[index].quantity, range: 1...max(1, min(available, Limits.quantity.upperBound)),
                                label: "Quantity", compact: true)
            }
            if over {
                Text(available == 0 ? "None Available now." : "Only \(available) Available now.")
                    .font(CKFont.caption.weight(.semibold))
                    .foregroundColor(CK.Palette.overdue)
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card).strokeBorder(over ? CK.Palette.overdue : CK.Palette.hairline, lineWidth: over ? 1.5 : 1))
    }

    @ViewBuilder
    private var summarySection: some View {
        if case .preparation(_, let summary) = source {
            VStack(alignment: .leading, spacing: 6) {
                CKLabel("preparation summary")
                Text(summary)
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confirmSection: some View {
        VStack(spacing: CK.Space.s) {
            Button {
                confirm()
            } label: {
                if submitting {
                    ProgressView().tint(CK.Palette.ink)
                } else {
                    Label("Confirm Checkout", systemImage: "checkmark.seal.fill")
                }
            }
            .buttonStyle(CKPrimaryButtonStyle())
            .disabled(lines.isEmpty || submitting)
            Text("Confirming moves every line from Available to \(mode == .loan ? "On Loan" : "In Use") at once — or nothing, if any line is no longer available.")
                .font(CKFont.caption)
                .foregroundColor(CK.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, CK.Space.xs)
    }

    private func confirm() {
        guard !submitting else { return }
        submitting = true
        var summary = ""
        var kitID: UUID?
        var runID: UUID?
        if case .preparation(let run, let text) = source {
            summary = text
            kitID = run.kitID
            runID = store.workshop.preparations.contains { $0.id == run.id } ? run.id : nil
        }
        let request = CheckoutRequest(
            operationID: operationID, mode: mode, purpose: purpose, recipientName: recipient, contactNote: contactNote,
            startedAt: min(startedAt, Date()), dueAt: dueAt, dueTimeZoneID: timeZoneID, lines: lines,
            conditionOutNote: conditionNote, preparationSummary: summary, kitID: kitID, preparationRunID: runID
        )
        do {
            let handover = try store.handovers.checkout(request)
            store.showToast(mode == .loan ? "Loaned to \(handover.recipientName)" : "Checked out for personal use")
            dismiss()
            onCompleted?(handover)
        } catch {
            submitting = false
            self.error = error.localizedDescription
        }
    }
}

/// Searchable list of time zones for a due date.
struct TimeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var search = ""

    var body: some View {
        let query = search.trimmed
        let zones = TimeZone.knownTimeZoneIdentifiers.filter {
            query.isEmpty || $0.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "_"))
        }
        NavigationView {
            List {
                Button("Device Time Zone (\(TimeZone.current.identifier))") {
                    selection = TimeZone.current.identifier
                    dismiss()
                }
                ForEach(zones, id: \.self) { zone in
                    Button {
                        selection = zone
                        dismiss()
                    } label: {
                        HStack {
                            Text(zone.replacingOccurrences(of: "_", with: " ")).foregroundColor(CK.Palette.ink)
                            Spacer()
                            if zone == selection { Image(systemName: "checkmark").foregroundColor(CK.Palette.copper) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "City or region")
            .navigationTitle("Time Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
