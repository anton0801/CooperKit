import SwiftUI

/// The workshop summary. Tool Records counts cards, Units counts physical things, and
/// Overdue counts handovers — not tools. No workshop value is shown anywhere here.
struct HomeView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationView {
            CKScroll {
                hero
                if store.workshop.tools.isEmpty {
                    firstToolCard
                } else {
                    figures
                }
                actions
                recentActivity
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(CK.Palette.velvet)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Hero

    private var hero: some View {
        let summary = store.summary
        return AdaptiveStack(spacing: CK.Space.s) {
            VStack(alignment: .leading, spacing: 6) {
                CKLabel("your workshop", color: CK.Palette.gold)
                if store.workshop.tools.isEmpty {
                    Text("Ready When You Are")
                        .font(CKFont.title)
                        .foregroundColor(CK.Palette.cream)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Add a tool and give it a place.")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.cream.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(summary.availableUnits)")
                        .ckFigure(52)
                        .foregroundColor(CK.Palette.cream)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Available Units")
                        .font(CKFont.headline)
                        .foregroundColor(CK.Palette.gold)
                    Text("of \(Format.units(summary.totalUnits)) in \(summary.toolRecords) \(summary.toolRecords == 1 ? "tool record" : "tool records")")
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.cream.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Sprite("ck04_home_case", size: CGSize(width: 154, height: 142))
        }
        .padding(CK.Space.m)
        .background(
            RoundedRectangle(cornerRadius: CK.Radius.hero, style: .continuous)
                .fill(LinearGradient(colors: [CK.Palette.velvet, CK.Palette.deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.hero, style: .continuous)
                .strokeBorder(CK.Palette.gold.opacity(0.55), lineWidth: 1.5)
        )
        .overlay(alignment: .bottomLeading) {
            Capsule().fill(CK.Palette.gold)
                .frame(width: 44, height: 3)
                .padding(.leading, CK.Space.m)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
        }
        .padding(.top, CK.Space.xs)
    }

    private var firstToolCard: some View {
        CKCard {
            Text("Add Your First Tool")
                .font(CKFont.title)
                .foregroundColor(CK.Palette.ink)
            Text("Start with the tool you reach for most. You'll choose where it lives, how many you have and, if you like, add a photo.")
                .font(CKFont.body)
                .foregroundColor(CK.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Tool") { router.isAddingTool = true }
                .buttonStyle(CKPrimaryButtonStyle())
        }
    }

    // MARK: - Figures

    private var figures: some View {
        let summary = store.summary
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: CK.Space.s), GridItem(.flexible())], spacing: CK.Space.s) {
            FigureTile(title: "Tool Records", value: summary.toolRecords, icon: "rectangle.stack.fill", tint: CK.Palette.velvet) {
                router.open(.tools)
            }
            FigureTile(title: "Total Units", value: summary.totalUnits, icon: "shippingbox.fill", tint: CK.Palette.velvet) {
                router.open(.tools)
            }
            FigureTile(title: UnitState.inUse.title, value: summary.inUse, icon: UnitState.inUse.icon, tint: CK.Palette.copper) {
                router.open(.handovers)
            }
            FigureTile(title: UnitState.onLoan.title, value: summary.onLoan, icon: UnitState.onLoan.icon, tint: CK.Palette.onLoan) {
                router.open(.handovers)
            }
            NavigationLink(destination: ServiceListView()) {
                FigureTileLabel(title: UnitState.needsService.title, value: summary.needsService,
                                icon: UnitState.needsService.icon, tint: CK.Palette.needsService)
            }
            .buttonStyle(CKTileButtonStyle())
            FigureTile(title: "Overdue Handovers", value: summary.overdueHandovers, icon: "exclamationmark.circle.fill",
                       tint: summary.overdueHandovers > 0 ? CK.Palette.overdue : CK.Palette.inkSecondary,
                       emphasis: summary.overdueHandovers > 0) {
                router.open(.handovers)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: CK.Space.s) {
            if !store.workshop.tools.isEmpty {
                Button {
                    router.isAddingTool = true
                } label: {
                    Label("Add Tool", systemImage: "plus")
                }
                .buttonStyle(CKPrimaryButtonStyle())
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: CK.Space.s), GridItem(.flexible(), spacing: CK.Space.s), GridItem(.flexible())],
                      spacing: CK.Space.s) {
                ShortcutTile(title: "Tools", icon: "wrench.and.screwdriver.fill") { router.open(.tools) }
                ShortcutTile(title: "Prepare Kit", icon: "checklist") { router.open(.kits) }
                ShortcutTile(title: "Handovers", icon: "arrow.left.arrow.right") { router.open(.handovers) }
                NavigationLink(destination: ServiceListView()) {
                    ShortcutLabel(title: "Service", icon: "wrench.fill")
                }
                .buttonStyle(CKTileButtonStyle())
                ShortcutTile(title: "Storage", icon: "archivebox.fill") { router.open(.storage) }
                NavigationLink(destination: HistoryView(toolID: nil)) {
                    ShortcutLabel(title: "History", icon: "clock.arrow.circlepath")
                }
                .buttonStyle(CKTileButtonStyle())
            }
        }
    }

    // MARK: - Activity

    private var recentActivity: some View {
        let recent = Array(store.workshop.activity.sorted { $0.at > $1.at }.prefix(5))
        return VStack(alignment: .leading, spacing: CK.Space.s) {
            CKSectionHeader(title: "Recent Activity") {
                if !recent.isEmpty {
                    NavigationLink("History", destination: HistoryView(toolID: nil))
                        .font(CKFont.subhead.weight(.semibold))
                        .foregroundColor(CK.Palette.velvet)
                        .frame(minHeight: 44)
                }
            }
            if recent.isEmpty {
                Text("Nothing recorded yet. Checkouts, returns and stock changes will appear here.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                CKCard(padding: CK.Space.s) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { CKDivider() }
                        ActivityRow(event: event, now: store.now)
                    }
                }
            }
        }
    }
}

private struct FigureTile: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    var emphasis = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FigureTileLabel(title: title, value: value, icon: icon, tint: tint, emphasis: emphasis)
        }
        .buttonStyle(CKTileButtonStyle())
    }
}

private struct FigureTileLabel: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    var emphasis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(CKFont.footnote.weight(.bold))
                    .foregroundColor(tint)
                Text(title)
                    .font(CKFont.footnote.weight(.semibold))
                    .foregroundColor(emphasis ? CK.Palette.overdue : CK.Palette.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(value)")
                .ckFigure(32)
                .foregroundColor(emphasis ? CK.Palette.overdue : CK.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CK.Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct ShortcutTile: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShortcutLabel(title: title, icon: icon)
        }
        .buttonStyle(CKTileButtonStyle())
    }
}

private struct ShortcutLabel: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CK.Palette.copper)
            Text(title)
                .font(CKFont.footnote.weight(.semibold))
                .foregroundColor(CK.Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, CK.Space.s)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One line of history, shared by Home, Tool Detail and History.
struct ActivityRow: View {
    let event: ActivityEvent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: CK.Space.s) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CK.Palette.copper)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CK.Palette.cream))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(CKFont.subhead.weight(.semibold))
                    .foregroundColor(CK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(CKFont.footnote)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: CK.Space.xs)
            Text(Calendar.current.isDate(event.at, inSameDayAs: now) ? Format.time(event.at) : Format.date(event.at))
                .font(CKFont.caption.monospacedDigit())
                .foregroundColor(CK.Palette.inkSecondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
