import SwiftUI

/// History: every recorded event, newest first, grouped by day. Opened from Home for
/// the whole workshop or from a tool page for that tool alone.
struct HistoryView: View {
    @EnvironmentObject private var store: WorkshopStore
    let toolID: UUID?

    @State private var group: ActivityGroup?
    @State private var search = ""

    var body: some View {
        let query = search.trimmed
        let events = store.workshop.activity
            .filter { toolID == nil || $0.toolIDs.contains(toolID!) }
            .filter { group == nil || $0.kind.group == group }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
            .sorted { $0.at > $1.at }
        let days = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.at) }
            .sorted { $0.key > $1.key }

        CKScroll(spacing: CK.Space.s) {
            if let toolID {
                Text(store.workshop.toolName(toolID))
                    .font(CKFont.title)
                    .foregroundColor(CK.Palette.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CK.Space.xs) {
                    chip("All", selected: group == nil) { group = nil }
                    ForEach(ActivityGroup.allCases, id: \.self) { item in
                        chip(item.title, selected: group == item) { group = item }
                    }
                }
            }
            if events.isEmpty {
                EmptyStateView(asset: nil, title: "Nothing Here Yet",
                               message: store.workshop.activity.isEmpty
                                ? "Every tool added, checkout, return and stock change is recorded here."
                                : "No events match this filter.")
            }
            ForEach(days, id: \.key) { day, items in
                CKLabel(Format.dayHeading(day, now: store.now).lowercased())
                    .padding(.top, CK.Space.xs)
                    .accessibilityAddTraits(.isHeader)
                CKCard(padding: CK.Space.s) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { CKDivider() }
                        link(for: event)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search history")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func link(for event: ActivityEvent) -> some View {
        if let id = event.handoverID, store.workshop.handover(id) != nil, event.kind.group == .handovers {
            NavigationLink(destination: HandoverDetailView(handoverID: id)) { ActivityRow(event: event, now: store.now) }
                .buttonStyle(.plain)
        } else if let id = event.serviceRecordID, store.workshop.serviceRecord(id) != nil {
            NavigationLink(destination: ServiceRecordView(recordID: id)) { ActivityRow(event: event, now: store.now) }
                .buttonStyle(.plain)
        } else if toolID == nil, event.toolIDs.count == 1, let id = event.toolIDs.first, store.workshop.tool(id) != nil {
            NavigationLink(destination: ToolDetailView(toolID: id)) { ActivityRow(event: event, now: store.now) }
                .buttonStyle(.plain)
        } else {
            ActivityRow(event: event, now: store.now)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CKFont.subhead.weight(.semibold))
                .foregroundColor(CK.Palette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Capsule().fill(selected ? CK.Palette.gold : CK.Palette.surface))
                .overlay(Capsule().strokeBorder(selected ? CK.Palette.copper.opacity(0.6) : CK.Palette.hairline, lineWidth: 1))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
