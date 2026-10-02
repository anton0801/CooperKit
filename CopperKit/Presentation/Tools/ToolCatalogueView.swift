import SwiftUI

/// Tools tab: find a tool and see what of it is free.
struct ToolCatalogueView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter

    private enum Scope: String, CaseIterable { case active = "Active", archived = "Archived" }

    @State private var search = ""
    @State private var scope: Scope = .active
    @State private var availableOnly = false
    @State private var category: ToolCategory?
    @State private var addToKit: Tool?

    private var filtered: [Tool] {
        let query = search.trimmed
        return store.workshop.tools
            .filter { scope == .active ? !$0.isArchived : $0.isArchived }
            .filter { !availableOnly || store.balance($0.id).available > 0 }
            .filter { category == nil || $0.category == category }
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.ownLabel.localizedCaseInsensitiveContains(query)
            }
            .sorted(by: WorkshopStore.byName)
    }

    var body: some View {
        CKScroll(spacing: CK.Space.s) {
            if store.workshop.tools.isEmpty {
                EmptyStateView(asset: "ck05_copper_hammer", title: "No Tools Yet",
                               message: "Add the tools you own, how many of each, and where they live.") {
                    Button {
                        router.isAddingTool = true
                    } label: {
                        Label("New Tool", systemImage: "plus")
                    }
                    .buttonStyle(CKPrimaryButtonStyle())
                }
                .padding(.top, CK.Space.xl)
            } else {
                filters
                let tools = filtered
                if tools.isEmpty {
                    Text(emptyMessage)
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, CK.Space.xl)
                } else {
                    Text("\(tools.count) \(tools.count == 1 ? "record" : "records")")
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                    ForEach(tools) { tool in
                        NavigationLink(destination: ToolDetailView(toolID: tool.id)) {
                            ToolRow(tool: tool, balance: store.balance(tool.id),
                                    locationName: store.workshop.location(tool.homeLocationID)?.name ?? "")
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: tool) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Name or Own Label")
        .navigationTitle("Tools")
        .toolbar {
            HomeToolbarItem(router: router)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.isAddingTool = true
                } label: {
                    Label("New Tool", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(CKFont.subhead.weight(.semibold))
                }
                .accessibilityLabel("New Tool")
            }
        }
        .background(RouteLink(route: $router.toolRoute) { ToolDetailView(toolID: $0) })
        .sheet(item: $addToKit) { tool in
            AddToKitSheet(tool: tool)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: CK.Space.xs) {
            CKSegmented(selection: $scope, options: Scope.allCases) { $0.rawValue }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CK.Space.xs) {
                    FilterChip(title: "Available", icon: "circle", isOn: $availableOnly)
                        .accessibilityHint("Shows only tools with at least one Available unit")
                    Menu {
                        Button("All Categories") { category = nil }
                        ForEach(ToolCategory.allCases, id: \.self) { item in
                            Button(item.title) { category = item }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category?.icon ?? "line.3.horizontal.decrease.circle")
                            Text(category?.title ?? "Category")
                                .font(CKFont.subhead.weight(.semibold))
                            Image(systemName: "chevron.down").font(CKFont.caption.weight(.bold))
                        }
                        .foregroundColor(CK.Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(category == nil ? CK.Palette.surface : CK.Palette.gold))
                        .overlay(Capsule().strokeBorder(CK.Palette.hairline, lineWidth: 1))
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Category filter: \(category?.title ?? "All")")
                }
            }
        }
    }

    private var emptyMessage: String {
        if scope == .archived { return "No archived tools." }
        if availableOnly { return "No tools with Available units match." }
        return "No tools match your search."
    }

    @ViewBuilder
    private func menu(for tool: Tool) -> some View {
        if !tool.isArchived {
            Button { addToKit = tool } label: { Label("Add to Kit", systemImage: "case") }
            Button {
                if store.perform("Can't Archive", { try store.tools.archive(tool.id) }) {
                    store.showToast("\(tool.name) archived")
                }
            } label: { Label("Archive", systemImage: "archivebox") }
        } else {
            Button {
                if store.perform("Can't Restore", { try store.tools.restore(tool.id) }) {
                    store.showToast("\(tool.name) restored")
                }
            } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
        }
    }
}

struct ToolRow: View {
    let tool: Tool
    let balance: ToolBalance
    let locationName: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        AdaptiveStack {
            ToolThumbnail(tool: tool)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(CKFont.headline)
                    .foregroundColor(CK.Palette.ink)
                    .lineLimit(2)
                Text([tool.ownLabel.nilIfBlank, tool.category.title].compactMap { $0 }.joined(separator: " · "))
                    .font(CKFont.footnote)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "archivebox")
                        .font(CKFont.caption)
                    Text(locationName)
                        .font(CKFont.footnote)
                        .lineLimit(1)
                }
                .foregroundColor(CK.Palette.inkSecondary)
                tags
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: CK.Space.xs) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                (Text("\(balance.available)").foregroundColor(balance.available > 0 ? CK.Palette.ink : CK.Palette.inkSecondary)
                    + Text("/\(balance.total)").foregroundColor(CK.Palette.inkSecondary))
                    .font(CKFont.rowFigure)
                CKLabel("available")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CK.Space.s)
        .background(
            RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                .fill(CK.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                .strokeBorder(CK.Palette.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var tags: some View {
        if tool.isArchived || balance.isOutOfStock || balance.needsService > 0 || balance.out > 0 {
            HStack(spacing: 4) {
                if tool.isArchived { TagView(text: "Archived", icon: "archivebox") }
                if balance.isOutOfStock { TagView(text: "Out of Stock", icon: "minus.circle", color: CK.Palette.overdue) }
                if balance.needsService > 0 { StatusBadge(.needsService, count: balance.needsService) }
                if balance.out > 0 {
                    StatusBadge(title: "\(balance.out) Out", icon: "arrow.up.forward", fill: CK.Palette.velvet)
                }
            }
            .padding(.top, 2)
        }
    }

    private var accessibilityText: String {
        var parts = [tool.name, "\(balance.available) of \(balance.total) available", locationName]
        if balance.out > 0 { parts.append("\(balance.out) out") }
        if balance.needsService > 0 { parts.append("\(balance.needsService) need service") }
        if tool.isArchived { parts.append("archived") }
        if balance.isOutOfStock { parts.append("out of stock") }
        return parts.joined(separator: ", ")
    }
}
