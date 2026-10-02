import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case tools, kits, handovers, storage

    var title: String {
        switch self {
        case .tools: return "Tools"
        case .kits: return "Kits"
        case .handovers: return "Handovers"
        case .storage: return "Storage"
        }
    }

    var icon: String {
        switch self {
        case .tools: return "wrench.and.screwdriver.fill"
        case .kits: return "case.fill"
        case .handovers: return "arrow.left.arrow.right"
        case .storage: return "archivebox.fill"
        }
    }
}

/// Which section is on screen, whether the Home summary is showing, and the one
/// programmatic push each section supports (used when an action in one place should
/// land on a record in another — a confirmed checkout opens its handover).
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .tools
    @Published var showsHome = true

    @Published var toolRoute: UUID?
    @Published var kitRoute: UUID?
    @Published var handoverRoute: UUID?
    @Published var locationRoute: UUID?

    /// Presents the Tool Editor for a new tool from anywhere.
    @Published var isAddingTool = false

    func open(_ tab: AppTab) {
        self.tab = tab
        showsHome = false
    }

    func goHome() {
        showsHome = true
    }

    func openTool(_ id: UUID) {
        open(.tools)
        toolRoute = id
    }

    func openHandover(_ id: UUID) {
        open(.handovers)
        handoverRoute = id
    }

    func openKit(_ id: UUID) {
        open(.kits)
        kitRoute = id
    }

    func openLocation(_ id: UUID) {
        open(.storage)
        locationRoute = id
    }
}

/// A hidden link at the root of a section that follows the router's route for it.
struct RouteLink<Destination: View>: View {
    @Binding var route: UUID?
    let destination: (UUID) -> Destination

    var body: some View {
        NavigationLink(
            isActive: Binding(get: { route != nil }, set: { if !$0 { route = nil } }),
            destination: {
                if let route { destination(route) } else { EmptyView() }
            },
            label: { EmptyView() }
        )
        .hidden()
        .accessibilityHidden(true)
    }
}
