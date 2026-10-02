import Foundation

/// The single error type the domain speaks.
///
/// Every case carries a sentence that is safe to show on screen: the rules in this
/// app are the owner's own bookkeeping rules, so a refusal is always something the
/// person can act on rather than an internal fault.
struct DomainError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

extension DomainError {
    static let recordMissing = DomainError("This record is no longer in your workshop.")
    static let toolMissing = DomainError("This tool is no longer in your workshop.")
    static let locationMissing = DomainError("This storage location no longer exists.")
    static let kitMissing = DomainError("This kit template no longer exists.")
    static let handoverMissing = DomainError("This handover no longer exists.")
    static let serviceMissing = DomainError("This service record no longer exists.")
}

/// A workshop document this build cannot read.
///
/// Told apart from corruption because the file itself is fine — it was written by a
/// newer version — and replacing it would destroy the owner's records.
struct WorkshopVersionError: LocalizedError, Equatable {
    let found: Int

    var errorDescription: String? {
        "Your workshop was saved by a newer version of Copper Kit (format \(found)). Update the app to open it. Nothing has been changed."
    }
}
