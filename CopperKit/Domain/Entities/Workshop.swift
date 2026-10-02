import Foundation

struct AppSettings: Equatable, Hashable {
    var defaultLoanDays: Int
    var defaultCurrencyCode: String
    var dueRemindersEnabled: Bool

    static func standard(locale: Locale = .current) -> AppSettings {
        AppSettings(
            defaultLoanDays: 7,
            defaultCurrencyCode: currency(of: locale) ?? "USD",
            dueRemindersEnabled: false
        )
    }

    private static func currency(of locale: Locale) -> String? {
        if #available(iOS 16, macOS 13, *) {
            return locale.currency?.identifier
        }
        return locale.currencyCode
    }
}

/// The whole of the owner's records. Every quantity on every screen is derived from
/// this one document through `StockLedger` — there are no separate numbers kept on cards.
struct Workshop: Equatable {
    static let currentSchemaVersion = 1

    var tools: [Tool] = []
    var locations: [StorageLocation] = []
    var kits: [KitTemplate] = []
    var preparations: [PreparationRun] = []
    var handovers: [Handover] = []
    var serviceRecords: [ServiceRecord] = []
    var movements: [StockMovement] = []
    var inventoryChecks: [InventoryCheck] = []
    var activity: [ActivityEvent] = []
    var settings: AppSettings = .standard()

    var isEmpty: Bool { tools.isEmpty && locations.isEmpty && kits.isEmpty }
}

extension Workshop {
    func tool(_ id: UUID) -> Tool? { tools.first { $0.id == id } }
    func location(_ id: UUID) -> StorageLocation? { locations.first { $0.id == id } }
    func kit(_ id: UUID) -> KitTemplate? { kits.first { $0.id == id } }
    func handover(_ id: UUID) -> Handover? { handovers.first { $0.id == id } }
    func serviceRecord(_ id: UUID) -> ServiceRecord? { serviceRecords.first { $0.id == id } }
    func preparation(_ id: UUID) -> PreparationRun? { preparations.first { $0.id == id } }

    func toolIndex(_ id: UUID) throws -> Int {
        guard let index = tools.firstIndex(where: { $0.id == id }) else { throw DomainError.toolMissing }
        return index
    }

    func locationIndex(_ id: UUID) throws -> Int {
        guard let index = locations.firstIndex(where: { $0.id == id }) else { throw DomainError.locationMissing }
        return index
    }

    func kitIndex(_ id: UUID) throws -> Int {
        guard let index = kits.firstIndex(where: { $0.id == id }) else { throw DomainError.kitMissing }
        return index
    }

    func handoverIndex(_ id: UUID) throws -> Int {
        guard let index = handovers.firstIndex(where: { $0.id == id }) else { throw DomainError.handoverMissing }
        return index
    }

    func serviceIndex(_ id: UUID) throws -> Int {
        guard let index = serviceRecords.firstIndex(where: { $0.id == id }) else { throw DomainError.serviceMissing }
        return index
    }

    func toolName(_ id: UUID) -> String { tool(id)?.name ?? "Removed Tool" }

    mutating func log(
        _ kind: ActivityKind,
        at: Date,
        title: String,
        detail: String = "",
        tools: [UUID] = [],
        handover: UUID? = nil,
        service: UUID? = nil,
        location: UUID? = nil,
        kit: UUID? = nil
    ) {
        activity.append(ActivityEvent(
            id: UUID(), at: at, kind: kind, title: title, detail: detail, toolIDs: tools,
            handoverID: handover, serviceRecordID: service, locationID: location, kitID: kit
        ))
    }
}
