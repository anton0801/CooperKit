import SwiftUI
import Combine

/// A repository the presentation layer can watch. The file repository in Data satisfies
/// it; the composition root declares the conformance so Presentation never imports Data.
protocol ObservableWorkshopRepository: WorkshopRepository {
    var onChange: ((Workshop) -> Void)? { get set }
    var loadProblem: String? { get }
}

/// The presentation layer's view of the workshop: the current document, the balances
/// derived from it, and the use cases screens call. It holds no rules of its own.
///
/// Used from the main thread only. Changes are applied synchronously, so a screen
/// opened straight after a save already sees the saved record.
final class WorkshopStore: ObservableObject {
    @Published private(set) var workshop: Workshop
    @Published private(set) var balances: [UUID: ToolBalance] = [:]
    /// Ticks every minute so Overdue appears without a relaunch.
    @Published private(set) var now: Date
    @Published var alert: AlertMessage?
    @Published var toast: String?

    let tools: ToolUseCases
    let locations: LocationUseCases
    let kits: KitUseCases
    let preparation: PreparationUseCases
    let handovers: HandoverUseCases
    let service: ServiceUseCases
    let inventory: InventoryUseCases
    let settingsUseCases: SettingsUseCases
    let photos: PhotoStoring

    private let repository: ObservableWorkshopRepository
    private let reminders: ReminderScheduling
    private let clock: Clock
    private var timer: AnyCancellable?
    private var toastTask: Task<Void, Never>?

    init(repository: ObservableWorkshopRepository, photos: PhotoStoring, reminders: ReminderScheduling, clock: Clock) {
        self.repository = repository
        self.photos = photos
        self.reminders = reminders
        self.clock = clock
        workshop = repository.workshop
        now = clock.now
        tools = ToolUseCases(repository: repository, clock: clock)
        locations = LocationUseCases(repository: repository, clock: clock)
        kits = KitUseCases(repository: repository, clock: clock)
        preparation = PreparationUseCases(repository: repository, clock: clock)
        handovers = HandoverUseCases(repository: repository, clock: clock)
        service = ServiceUseCases(repository: repository, clock: clock)
        inventory = InventoryUseCases(repository: repository, clock: clock)
        settingsUseCases = SettingsUseCases(repository: repository, photos: photos)
        balances = StockLedger.balances(workshop)

        if let problem = repository.loadProblem {
            alert = AlertMessage(title: "Workshop Not Opened", message: problem)
        }
        repository.onChange = { [weak self] workshop in
            self?.apply(workshop)
        }
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshClock() }
        syncReminders()
    }

    private func apply(_ workshop: Workshop) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.workshop = workshop
        balances = StockLedger.balances(workshop)
        now = clock.now
        syncReminders()
    }

    func refreshClock() {
        now = clock.now
    }

    // MARK: - Reads

    func balance(_ toolID: UUID) -> ToolBalance { balances[toolID] ?? .zero }

    var summary: WorkshopSummary { StockLedger.summary(workshop, now: now) }

    var activeTools: [Tool] {
        workshop.tools.filter { !$0.isArchived }.sorted(by: Self.byName)
    }

    var sortedLocations: [StorageLocation] {
        workshop.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var overdueCount: Int {
        workshop.handovers.filter { $0.status(at: now) == .overdue }.count
    }

    var openServiceCount: Int {
        workshop.serviceRecords.filter(\.isOpen).count
    }

    static func byName(_ a: Tool, _ b: Tool) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    // MARK: - Actions

    /// Runs an action and turns a refusal into an alert. Returns whether it succeeded.
    @discardableResult
    func perform(_ action: () throws -> Void) -> Bool {
        perform("Not Saved", action)
    }

    @discardableResult
    func perform(_ title: String, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            alert = AlertMessage(title: title, message: error.localizedDescription)
            return false
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        UIAccessibility.post(notification: .announcement, argument: message)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func updateSettings(_ settings: AppSettings) -> Bool {
        perform { try settingsUseCases.update(settings) }
    }

    func requestReminderPermission(_ completion: @escaping (Bool) -> Void) {
        reminders.requestAuthorization(completion)
    }

    func deleteAllData() -> Bool {
        perform("Could Not Delete") { try settingsUseCases.deleteAll() }
    }

    private func syncReminders() {
        let names = Dictionary(uniqueKeysWithValues: workshop.tools.map { ($0.id, $0.name) })
        reminders.sync(handovers: workshop.handovers, toolNames: names,
                       enabled: workshop.settings.dueRemindersEnabled, now: clock.now)
    }
}

struct AlertMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
