import SwiftUI

/// The section bar: a deep-blue velvet slab under a copper rule. The active section sits
/// on a gold plate (the case's brass nameplate); labels are always visible. While Home
/// is showing no plate is lit, and tapping any section leaves Home.
struct CKTabBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: WorkshopStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, CK.Space.xs)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // Like the system bar: capped size, with the large content viewer for bigger settings.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background(
            CK.Palette.deepBlue
                .overlay(Rectangle().fill(CK.Palette.copper).frame(height: 1.5), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: AppTab) -> some View {
        let active = !router.showsHome && router.tab == tab
        let badge = tab == .handovers ? store.overdueCount : 0
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                router.open(tab)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(CK.Palette.overdue))
                                .overlay(Capsule().strokeBorder(CK.Palette.deepBlue, lineWidth: 1.5))
                                .offset(x: 12, y: -6)
                        }
                    }
                Text(tab.title)
                    .font(.system(.caption2).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(active ? CK.Palette.ink : CK.Palette.cream.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CK.Palette.gold)
                        .overlay(rivets)
                        .matchedGeometryEffect(id: "plate", in: plate)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.icon)
        }
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityValue(badge > 0 ? "\(badge) overdue" : "")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    /// Two tiny rivets on the nameplate.
    private var rivets: some View {
        HStack {
            Circle().fill(CK.Palette.copper.opacity(0.7)).frame(width: 4, height: 4)
            Spacer()
            Circle().fill(CK.Palette.copper.opacity(0.7)).frame(width: 4, height: 4)
        }
        .padding(.horizontal, 7)
        .accessibilityHidden(true)
    }
}
