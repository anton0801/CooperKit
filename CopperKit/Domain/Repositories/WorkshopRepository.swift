import Foundation

/// The owner's records, as the domain is allowed to see them.
///
/// Every change goes through `transact`: the closure edits a copy, and only when it
/// returns without throwing *and* the copy has been written does it become the
/// workshop everyone reads. A checkout whose third line fails leaves the first two
/// exactly where they were — there is no partial commit.
protocol WorkshopRepository: AnyObject {
    var workshop: Workshop { get }

    @discardableResult
    func transact<T>(_ change: (inout Workshop) throws -> T) throws -> T

    /// Swaps the whole document; used only by Delete All Data.
    func replaceAll(with workshop: Workshop) throws
}

/// The owner's own tool photos, stored beside the document and referenced by name.
protocol PhotoStoring: AnyObject {
    /// Stores already-encoded JPEG data and returns its identifier.
    func save(_ jpegData: Data) throws -> String
    func load(_ id: String) -> Data?
    func delete(_ ids: [String])
    func deleteAll()
}

/// Local reminders to the owner about their own due dates. The app never messages
/// the people who borrowed something.
protocol ReminderScheduling: AnyObject {
    func sync(handovers: [Handover], toolNames: [UUID: String], enabled: Bool, now: Date)
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)
}
