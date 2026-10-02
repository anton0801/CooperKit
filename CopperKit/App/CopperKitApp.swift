import SwiftUI

@main
struct CopperKitApp: App {
    @StateObject private var store: WorkshopStore
    @StateObject private var router = AppRouter()

    init() {
        CKAppearance.apply()
        _store = StateObject(wrappedValue: AppContainer.makeStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .preferredColorScheme(.light)
                .tint(CK.Palette.velvet)
        }
    }
}
