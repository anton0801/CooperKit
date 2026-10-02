import XCTest
@testable import CopperKit

/// In-memory repository with the same transaction behaviour as the file one: a change
/// that throws leaves nothing behind.
final class InMemoryRepository: WorkshopRepository {
    private(set) var workshop = Workshop()
    private(set) var writes = 0

    @discardableResult
    func transact<T>(_ change: (inout Workshop) throws -> T) throws -> T {
        var candidate = workshop
        let result = try change(&candidate)
        if candidate != workshop {
            workshop = candidate
            writes += 1
        }
        return result
    }

    func replaceAll(with workshop: Workshop) throws {
        self.workshop = workshop
    }
}

final class MutableClock: Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(days: Double) { now = now.addingTimeInterval(days * 86_400) }
}

final class MemoryPhotos: PhotoStoring {
    var files: [String: Data] = [:]
    func save(_ jpegData: Data) throws -> String { let id = UUID().uuidString + ".jpg"; files[id] = jpegData; return id }
    func load(_ id: String) -> Data? { files[id] }
    func delete(_ ids: [String]) { ids.forEach { files[$0] = nil } }
    func deleteAll() { files = [:] }
}

/// A workshop wired to use cases, with helpers to build the common starting points.
final class Harness {
    let repository = InMemoryRepository()
    let clock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000)) // whole seconds
    lazy var tools = ToolUseCases(repository: repository, clock: clock, locale: Locale(identifier: "en_US"))
    lazy var locations = LocationUseCases(repository: repository, clock: clock)
    lazy var kits = KitUseCases(repository: repository, clock: clock)
    lazy var preparation = PreparationUseCases(repository: repository, clock: clock)
    lazy var handovers = HandoverUseCases(repository: repository, clock: clock)
    lazy var service = ServiceUseCases(repository: repository, clock: clock)
    lazy var inventory = InventoryUseCases(repository: repository, clock: clock)

    var workshop: Workshop { repository.workshop }

    func balance(_ id: UUID) -> ToolBalance { StockLedger.balance(of: id, in: workshop) }

    @discardableResult
    func location(_ name: String = "Garage Shelf") throws -> StorageLocation {
        var draft = LocationDraft()
        draft.name = name
        return try locations.create(draft)
    }

    @discardableResult
    func tool(_ name: String, quantity: Int = 1, mode: TrackingMode = .identicalUnits, at location: StorageLocation? = nil) throws -> Tool {
        let place = try location ?? workshop.locations.first ?? self.location()
        var draft = ToolDraft(currencyCode: "EUR")
        draft.name = name
        draft.trackingMode = mode
        draft.initialQuantity = quantity
        draft.homeLocationID = place.id
        return try tools.create(draft)
    }

    func checkoutRequest(_ lines: [(UUID, Int)], mode: HandoverMode = .loan, operation: UUID = UUID(),
                         startedAt: Date? = nil, dueInDays: Double = 7) -> CheckoutRequest {
        let start = startedAt ?? clock.now
        return CheckoutRequest(
            operationID: operation, mode: mode, purpose: "Deck repair", recipientName: mode == .loan ? "Anna" : "",
            contactNote: "", startedAt: start, dueAt: start.addingTimeInterval(dueInDays * 86_400),
            dueTimeZoneID: "Europe/Berlin", lines: lines.map { .init(toolID: $0.0, quantity: $0.1) },
            conditionOutNote: "", preparationSummary: "", kitID: nil, preparationRunID: nil
        )
    }
}
