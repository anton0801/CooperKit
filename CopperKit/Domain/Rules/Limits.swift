import Foundation

/// Field limits from the product specification, in one place so forms, validators and
/// tests agree on them.
enum Limits {
    static let nameLength = 1...80
    static let notesMax = 3000
    static let purposeMax = 500
    static let checkoutPurpose = 1...120
    static let recipientMax = 80
    static let contactNoteMax = 200
    static let conditionNoteMax = 500
    static let labelMax = 40
    static let serialMax = 60
    static let reasonMax = 200
    static let issueMax = 500
    static let quantity = 1...999
    static let photosMax = 5
    static let kitLines = 1...50
    static let costMax = Decimal(string: "9999999.99")!
    static let loanDays = 1...365
}

/// Pure validation helpers. Each returns the normalised value or throws a sentence the
/// owner can act on.
enum Validate {
    static func name(_ raw: String, field: String = "Name") throws -> String {
        let value = raw.trimmed
        guard !value.isEmpty else { throw DomainError("\(field) is required.") }
        guard value.count <= Limits.nameLength.upperBound else {
            throw DomainError("\(field) must be \(Limits.nameLength.upperBound) characters or fewer.")
        }
        return value
    }

    static func text(_ raw: String, max: Int, field: String) throws -> String {
        let value = raw.trimmed
        guard value.count <= max else { throw DomainError("\(field) must be \(max) characters or fewer.") }
        return value
    }

    static func required(_ raw: String, max: Int, field: String) throws -> String {
        let value = raw.trimmed
        guard !value.isEmpty else { throw DomainError("\(field) is required.") }
        guard value.count <= max else { throw DomainError("\(field) must be \(max) characters or fewer.") }
        return value
    }

    static func quantity(_ value: Int, field: String = "Quantity") throws -> Int {
        guard Limits.quantity.contains(value) else {
            throw DomainError("\(field) must be a whole number from \(Limits.quantity.lowerBound) to \(Limits.quantity.upperBound).")
        }
        return value
    }

    static func positive(_ value: Int, field: String = "Quantity") throws -> Int {
        guard value > 0 else { throw DomainError("\(field) must be greater than zero.") }
        return value
    }
}
