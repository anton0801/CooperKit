import Foundation

/// The composition root: the only place that knows both the Data implementations and
/// the Presentation store, and wires one to the other.
enum AppContainer {
    @MainActor
    static func makeStore() -> WorkshopStore {
        let clock = SystemClock()
        let paths = storagePaths()
        let repository = FileWorkshopRepository(paths: paths, clock: clock)
        let store = WorkshopStore(
            repository: repository,
            photos: FilePhotoStore(paths: paths),
            reminders: NotificationReminderScheduler(),
            clock: clock
        )
        #if DEBUG
        DebugSeed.applyIfRequested(to: store)
        #endif
        return store
    }

    private static func storagePaths() -> StoragePaths {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestReset") {
            // A fresh, isolated store for UI tests; never used by release builds.
            let paths = StoragePaths.standard(folderName: "CopperKitUITest")
            try? FileManager.default.removeItem(at: paths.root)
            if arguments.contains("-skipOnboarding") {
                UserDefaults.standard.set(true, forKey: "ck.onboardingDone")
            } else {
                UserDefaults.standard.set(false, forKey: "ck.onboardingDone")
            }
            return paths
        }
        #endif
        return .standard()
    }
}

extension FileWorkshopRepository: ObservableWorkshopRepository {}
