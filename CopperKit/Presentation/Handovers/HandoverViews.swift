import SwiftUI

/// Handovers tab: what is out, with whom, and what is overdue.
struct HandoverListView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter

    private enum Filter: String, CaseIterable { case open = "Open", overdue = "Overdue", returned = "Returned", all = "All" }
    @State private var filter: Filter = .open

    var body: some View {
        let now = store.now
        let handovers = store.workshop.handovers.filter { handover in
            switch filter {
            case .open: return !handover.isClosed
            case .overdue: return handover.status(at: now) == .overdue
            case .returned: return handover.isClosed
            case .all: return true
            }
        }
        .sorted { a, b in
            if a.isClosed != b.isClosed { return !a.isClosed }
            return a.isClosed ? (a.closedAt ?? a.startedAt) > (b.closedAt ?? b.startedAt) : a.dueAt < b.dueAt
        }

        CKScroll(spacing: CK.Space.s) {
            CKSegmented(selection: $filter, options: Filter.allCases) { item in
                item == .overdue && store.overdueCount > 0 ? "Overdue (\(store.overdueCount))" : item.rawValue
            }
            if handovers.isEmpty {
                EmptyStateView(asset: "ck11_closed_case", assetSize: CGSize(width: 100, height: 90),
                               title: emptyTitle, message: emptyMessage) {
                    if filter == .open && !store.workshop.tools.isEmpty {
                        HStack(spacing: CK.Space.s) {
                            Button("Tools") { router.open(.tools) }.buttonStyle(CKSecondaryButtonStyle())
                            Button("Kits") { router.open(.kits) }.buttonStyle(CKSecondaryButtonStyle())
                        }
                    }
                }
            } else {
                ForEach(handovers) { handover in
                    NavigationLink(destination: HandoverDetailView(handoverID: handover.id)) {
                        HandoverRow(handover: handover, now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Handovers")
        .toolbar { HomeToolbarItem(router: router) }
        .background(RouteLink(route: $router.handoverRoute) { HandoverDetailView(handoverID: $0) })
    }

    private var emptyTitle: String {
        switch filter {
        case .open: return "Nothing Is Out"
        case .overdue: return "Nothing Overdue"
        case .returned: return "No Returns Yet"
        case .all: return "No Handovers Yet"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .open, .all: return "Check out from a tool page, or prepare a kit and review its checkout."
        case .overdue: return "Every open handover is still within its due date."
        case .returned: return "Handovers appear here once every unit is back."
        }
    }
}

struct HandoverRow: View {
    let handover: Handover
    let now: Date
    var focusToolID: UUID?

    var body: some View {
        let status = handover.status(at: now)
        return VStack(alignment: .leading, spacing: 6) {
            AdaptiveStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(handover.purpose)
                        .font(CKFont.headline)
                        .foregroundColor(CK.Palette.ink)
                        .lineLimit(3)
                    HStack(spacing: 4) {
                        Image(systemName: handover.mode == .loan ? UnitState.onLoan.icon : UnitState.inUse.icon)
                            .font(CKFont.caption)
                        Text(handover.mode == .loan ? "Loan · \(handover.recipientName)" : "Personal Use")
                            .font(CKFont.footnote)
                    }
                    .foregroundColor(CK.Palette.inkSecondary)
                }
                Spacer()
                StatusBadge(handover: status)
            }
            AdaptiveStack(spacing: 4) {
                Text(dateLine(status))
                    .font(CKFont.footnote)
                    .foregroundColor(status == .overdue ? CK.Palette.overdue : CK.Palette.inkSecondary)
                Spacer(minLength: 0)
                Text(outstandingLine)
                    .font(CKFont.footnote.weight(.semibold).monospacedDigit())
                    .foregroundColor(CK.Palette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous).fill(CK.Palette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                .strokeBorder(status == .overdue ? CK.Palette.overdue.opacity(0.6) : CK.Palette.hairline, lineWidth: status == .overdue ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func dateLine(_ status: HandoverStatus) -> String {
        switch status {
        case .returned: return "Returned \(Format.date(handover.closedAt ?? handover.startedAt))"
        case .overdue: return "Was due \(Format.due(handover))"
        case .open: return "Due \(Format.due(handover))"
        }
    }

    private var outstandingLine: String {
        if let focusToolID {
            let out = handover.lines.filter { $0.toolID == focusToolID }.reduce(0) { $0 + handover.outstanding(forLine: $1) }
            return "\(out) of this tool out"
        }
        if handover.isClosed { return "\(Format.units(handover.totalOut)) · all back" }
        return "\(handover.totalOutstanding) of \(handover.totalOut) still out"
    }
}

/// One handover: who has what, what came back and in what state.
struct HandoverDetailView: View {
    @EnvironmentObject private var store: WorkshopStore
    let handoverID: UUID

    private enum ActiveSheet: Identifiable {
        case returning, changeDue, share
        var id: Int { hashValue }
    }

    @State private var sheet: ActiveSheet?

    var body: some View {
        if let handover = store.workshop.handover(handoverID) {
            content(handover)
        } else {
            EmptyStateView(asset: nil, title: "Handover Removed", message: DomainError.handoverMissing.message)
                .background(CK.Palette.background.ignoresSafeArea())
        }
    }

    private func content(_ handover: Handover) -> some View {
        let status = handover.status(at: store.now)
        return CKScroll {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StatusBadge(handover: status)
                    TagView(text: handover.mode.title, icon: handover.mode == .loan ? "person" : "hammer", color: CK.Palette.velvet)
                }
                Text(handover.purpose)
                    .font(CKFont.display)
                    .foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if handover.mode == .loan {
                    Text("With \(handover.recipientName)")
                        .font(CKFont.title3)
                        .foregroundColor(CK.Palette.ink)
                    if !handover.contactNote.isEmpty {
                        Text(handover.contactNote).font(CKFont.subhead).foregroundColor(CK.Palette.inkSecondary)
                    }
                }
            }

            CKCard {
                KeyValueRow(key: "started", value: Format.dateTime(handover.startedAt))
                KeyValueRow(key: "due", value: Format.due(handover),
                            valueColor: status == .overdue ? CK.Palette.overdue : CK.Palette.ink)
                if status != .returned {
                    Text(status == .overdue
                         ? "Overdue since \(Format.relativeDue(handover.dueAt, now: store.now))."
                         : "Due \(Format.relativeDue(handover.dueAt, now: store.now)).")
                        .font(CKFont.footnote.weight(.semibold))
                        .foregroundColor(status == .overdue ? CK.Palette.overdue : CK.Palette.inkSecondary)
                }
                if let closed = handover.closedAt {
                    KeyValueRow(key: "returned", value: Format.dateTime(closed), valueColor: CK.Palette.returned)
                }
                if !handover.kitNameSnapshot.isEmpty {
                    KeyValueRow(key: "kit", value: handover.kitNameSnapshot)
                }
            }

            if status != .returned {
                Button { sheet = .returning } label: { Label("Record Return", systemImage: "arrow.down.backward.circle.fill") }
                    .buttonStyle(CKPrimaryButtonStyle())
            }
            HStack(spacing: CK.Space.s) {
                if status != .returned {
                    Button { sheet = .changeDue } label: { Label("Change Due", systemImage: "calendar") }
                        .buttonStyle(CKSecondaryButtonStyle())
                }
                Button { sheet = .share } label: { Label("Share Summary", systemImage: "square.and.arrow.up") }
                    .buttonStyle(CKSecondaryButtonStyle())
            }
            NavigationLink(destination: PrepareKitView(source: .repeatHandover(handover.id))) {
                Label("Repeat This Kit", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CKSecondaryButtonStyle())
            Text("Repeat copies the list of tools and quantities — not the dates, notes or return marks.")
                .font(CKFont.caption)
                .foregroundColor(CK.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            CKSectionHeader("Lines")
            ForEach(handover.lines) { line in
                lineCard(handover, line)
            }

            if !handover.conditionOutNote.isEmpty {
                CKSectionHeader("Condition Out")
                CKCard {
                    Text(handover.conditionOutNote).font(CKFont.body).foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !handover.preparationSummary.isEmpty {
                CKSectionHeader("Preparation Summary")
                CKCard {
                    Text(handover.preparationSummary).font(CKFont.subhead).foregroundColor(CK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !handover.returns.isEmpty {
                CKSectionHeader("Returns")
                ForEach(handover.returns.sorted { $0.returnedAt > $1.returnedAt }) { record in
                    returnCard(handover, record)
                }
            }
        }
        .navigationTitle(handover.purpose)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { item in
            switch item {
            case .returning:
                ReturnView(handoverID: handover.id).environmentObject(store)
            case .changeDue:
                ChangeDueSheet(handover: handover).environmentObject(store)
            case .share:
                ShareSheet(items: [HandoverSummary.text(handover, now: store.now)])
                    .ignoresSafeArea()
            }
        }
    }

    private func lineCard(_ handover: Handover, _ line: HandoverLine) -> some View {
        let back = handover.returned(forLine: line.id)
        let outstanding = handover.outstanding(forLine: line)
        let tool = store.workshop.tool(line.toolID)
        return VStack(alignment: .leading, spacing: CK.Space.xs) {
            HStack(spacing: CK.Space.s) {
                ToolThumbnail(tool: tool, size: 40)
                if tool != nil {
                    NavigationLink(destination: ToolDetailView(toolID: line.toolID)) {
                        Text(line.toolNameSnapshot).font(CKFont.headline).foregroundColor(CK.Palette.velvet)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(line.toolNameSnapshot).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                }
                Spacer()
                if outstanding > 0 {
                    StatusBadge(title: "\(outstanding) Still Out", icon: "arrow.up.forward", fill: CK.Palette.velvet)
                } else {
                    StatusBadge(title: "All Back", icon: "checkmark", fill: CK.Palette.returned)
                }
            }
            HStack(spacing: CK.Space.m) {
                figure("out", line.quantity)
                figure("available", back.available)
                figure("service", back.needsService)
                if back.lost > 0 { figure("lost", back.lost) }
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card).strokeBorder(CK.Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(CKFont.smallFigure).foregroundColor(CK.Palette.ink)
            CKLabel(label)
        }
    }

    private func returnCard(_ handover: Handover, _ record: ReturnRecord) -> some View {
        CKCard {
            HStack {
                Text(Format.dateTime(record.returnedAt)).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                Spacer()
            }
            ForEach(record.lines, id: \.lineID) { line in
                let name = handover.lines.first { $0.id == line.lineID }?.toolNameSnapshot ?? "Tool"
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(CKFont.subhead.weight(.semibold)).foregroundColor(CK.Palette.ink)
                    Text(returnParts(line)).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
                    if !line.issueNote.isEmpty {
                        Text("Issue: \(line.issueNote)").font(CKFont.footnote).foregroundColor(CK.Palette.needsService)
                    }
                }
            }
            if !record.note.isEmpty {
                Text(record.note).font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
            }
        }
    }

    private func returnParts(_ line: ReturnLine) -> String {
        var parts: [String] = []
        if line.returnedToAvailable > 0 { parts.append("\(line.returnedToAvailable) to Available") }
        if line.needsService > 0 { parts.append("\(line.needsService) to Needs Service") }
        if line.lost > 0 { parts.append("\(line.lost) lost") }
        return parts.joined(separator: " · ")
    }
}

/// Partial Return: line by line, working units back to Available, damaged units to
/// Needs Service with what's wrong, and — only when confirmed — units that won't return.
struct ReturnView: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let handoverID: UUID

    @State private var operationID = UUID()
    @State private var returnedAt = Date()
    @State private var entries: [UUID: ReturnRequest.Line] = [:]
    @State private var note = ""
    @State private var error: String?
    @State private var submitting = false
    @State private var confirmLost = false

    var body: some View {
        NavigationView {
            if let handover = store.workshop.handover(handoverID) {
                form(handover)
            } else {
                EmptyStateView(asset: nil, title: "Handover Removed", message: DomainError.handoverMissing.message)
            }
        }
        .interactiveDismissDisabled(submitting)
    }

    private func form(_ handover: Handover) -> some View {
        let open = handover.lines.filter { handover.outstanding(forLine: $0) > 0 }
        let entered = entries.values.reduce(0) { $0 + $1.total }
        let lost = entries.values.reduce(0) { $0 + $1.lost }
        return ScrollViewReader { proxy in
            CKScroll {
                Text(handover.purpose).font(CKFont.title).foregroundColor(CK.Palette.ink)
                Text("\(handover.totalOutstanding) of \(handover.totalOut) still out · \(handover.holderLabel)")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                if let error { NoticeView(text: error, tone: .error).id("error") }

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(label: "Returned At", required: true)
                    DatePicker("Returned At", selection: $returnedAt, in: handover.startedAt...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                Button("Everything Back in Working Order") {
                    for line in open {
                        entries[line.id] = .init(lineID: line.id, toAvailable: handover.outstanding(forLine: line))
                    }
                }
                .buttonStyle(CKSecondaryButtonStyle())

                ForEach(open) { line in
                    lineEditor(handover, line)
                }

                CKTextArea(label: "Return Note", text: $note, limit: Limits.conditionNoteMax, minHeight: 64)

                let remaining = handover.totalOutstanding - entered
                NoticeView(text: entered == 0
                           ? "Enter what came back. Anything not entered stays out."
                           : "Returning \(Format.units(entered)). \(remaining == 0 ? "Everything will be back — the handover becomes Returned." : "\(remaining) will still be out and the handover stays open.")",
                           tone: .info)

                Button {
                    if lost > 0 { confirmLost = true } else { submit(handover) }
                } label: {
                    Label("Confirm Return", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(CKPrimaryButtonStyle())
                .disabled(entered == 0 || submitting)
            }
            .onChange(of: error) { value in if value != nil { withAnimation { proxy.scrollTo("error", anchor: .top) } } }
        }
        .navigationTitle("Record Return")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .confirmationDialog("Record \(Format.units(lost)) as lost?", isPresented: $confirmLost, titleVisibility: .visible) {
            Button("Confirm Return", role: .destructive) { submit(handover) }
        } message: {
            Text("Lost units leave the total for good. The history keeps a record of them.")
        }
    }

    private func lineEditor(_ handover: Handover, _ line: HandoverLine) -> some View {
        let outstanding = handover.outstanding(forLine: line)
        let entry = entries[line.id] ?? .init(lineID: line.id)
        func binding(_ keyPath: WritableKeyPath<ReturnRequest.Line, Int>) -> Binding<Int> {
            Binding(
                get: { (entries[line.id] ?? .init(lineID: line.id))[keyPath: keyPath] },
                set: { value in
                    var current = entries[line.id] ?? .init(lineID: line.id)
                    current[keyPath: keyPath] = value
                    entries[line.id] = current
                }
            )
        }
        let over = entry.total > outstanding
        return VStack(alignment: .leading, spacing: CK.Space.s) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.toolNameSnapshot).font(CKFont.headline).foregroundColor(CK.Palette.ink)
                    Text("\(outstanding) still out").font(CKFont.footnote).foregroundColor(CK.Palette.inkSecondary)
                }
                Spacer()
                Button("All Back") {
                    entries[line.id] = .init(lineID: line.id, toAvailable: outstanding)
                }
                .buttonStyle(CKTextButtonStyle())
            }
            stepperRow("Back to Available", icon: UnitState.available.icon, color: CK.Palette.available,
                       value: binding(\.toAvailable), max: outstanding)
            stepperRow("Needs Service", icon: UnitState.needsService.icon, color: CK.Palette.needsService,
                       value: binding(\.needsService), max: outstanding)
            if entry.needsService > 0 {
                CKTextField(label: "What Needs Attention", text: Binding(
                    get: { entries[line.id]?.issueNote ?? "" },
                    set: { value in
                        var current = entries[line.id] ?? .init(lineID: line.id)
                        current.issueNote = value
                        entries[line.id] = current
                    }
                ), placeholder: "Cracked handle, battery won't hold charge", required: true, limit: Limits.issueMax)
            }
            stepperRow("Lost", icon: "questionmark.circle.fill", color: CK.Palette.overdue, value: binding(\.lost), max: outstanding)
            if over {
                Text("Only \(outstanding) still out — reduce the numbers above.")
                    .font(CKFont.caption.weight(.semibold))
                    .foregroundColor(CK.Palette.overdue)
            }
        }
        .padding(CK.Space.s)
        .background(RoundedRectangle(cornerRadius: CK.Radius.card).fill(CK.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: CK.Radius.card).strokeBorder(over ? CK.Palette.overdue : CK.Palette.hairline, lineWidth: over ? 1.5 : 1))
    }

    private func stepperRow(_ title: String, icon: String, color: Color, value: Binding<Int>, max: Int) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(title).font(CKFont.subhead).foregroundColor(CK.Palette.ink)
            Spacer()
            QuantityStepper(value: value, range: 0...Swift.max(0, max), label: title, compact: true)
        }
    }

    private func submit(_ handover: Handover) {
        guard !submitting else { return }
        submitting = true
        let request = ReturnRequest(operationID: operationID, handoverID: handover.id, returnedAt: min(returnedAt, Date()),
                                    note: note, lines: Array(entries.values))
        do {
            let updated = try store.handovers.recordReturn(request)
            store.showToast(updated.isClosed ? "All returned" : "Return recorded · \(updated.totalOutstanding) still out")
            dismiss()
        } catch {
            submitting = false
            self.error = error.localizedDescription
        }
    }
}

/// Change the due date (and the time zone it is kept in).
struct ChangeDueSheet: View {
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.dismiss) private var dismiss
    let handover: Handover

    @State private var dueAt = Date()
    @State private var zone = TimeZone.current.identifier
    @State private var pickingZone = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationView {
            CKScroll {
                if let error { NoticeView(text: error, tone: .error) }
                Text(handover.purpose).font(CKFont.title).foregroundColor(CK.Palette.ink)
                DatePicker("Due At", selection: $dueAt, in: handover.startedAt..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                Button { pickingZone = true } label: {
                    Label("Time Zone: \(zone.replacingOccurrences(of: "_", with: " "))", systemImage: "globe")
                }
                .buttonStyle(CKTextButtonStyle())
            }
            .navigationTitle("Change Due")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.handovers.changeDue(handover.id, dueAt: dueAt, timeZoneID: zone)
                            store.showToast("Due date changed")
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .font(CKFont.button)
                }
            }
            .sheet(isPresented: $pickingZone) { TimeZonePicker(selection: $zone) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            dueAt = handover.dueAt
            zone = handover.dueTimeZoneID
        }
    }
}
