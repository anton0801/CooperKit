import SwiftUI

/// Onboarding on first launch, then the section shell with Home over it.
struct RootView: View {
    @AppStorage("ck.onboardingDone") private var onboardingDone = false
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            CK.Palette.background.ignoresSafeArea()
            if onboardingDone {
                SectionShell()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    router.showsHome = true
                    withAnimation(.easeInOut(duration: 0.3)) { onboardingDone = true }
                }
                .transition(.opacity)
            }
        }
        .alert(item: $store.alert) { message in
            Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK")))
        }
    }
}

/// The four sections in a system `TabView` (so each keeps its place and only the
/// visible one is in the accessibility tree) with its own bar hidden, the Home summary
/// layered above them, and the custom section bar along the bottom.
struct SectionShell: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TabView(selection: $router.tab) {
                    section { ToolCatalogueView() }.tag(AppTab.tools)
                    section { KitListView() }.tag(AppTab.kits)
                    section { HandoverListView() }.tag(AppTab.handovers)
                    section { StorageListView() }.tag(AppTab.storage)
                }
                .accessibilityHidden(router.showsHome)

                if router.showsHome {
                    HomeView()
                        .accessibilityAddTraits(.isModal)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9), value: router.showsHome)

            CKTabBar()
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.toast)
        .sheet(isPresented: $router.isAddingTool) {
            ToolEditorView(mode: .create) { tool in
                router.openTool(tool.id)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.refreshClock() }
        }
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationView { content() }
            .navigationViewStyle(.stack)
    }
}

/// Leading toolbar item for section roots.
struct HomeToolbarItem: ToolbarContent {
    let router: AppRouter

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HomeButton { router.goHome() }
        }
    }
}
