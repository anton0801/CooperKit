import Foundation

/// What the owner typed into the private cost fields.
struct CostInput: Equatable {
    var amountText: String = ""
    var currencyCode: String
    /// Set only by the explicit Enter Zero action. A typed "0" alone is refused, so an
    /// unknown price can never be saved as free by accident.
    var zeroConfirmed: Bool = false

    init(amountText: String = "", currencyCode: String, zeroConfirmed: Bool = false) {
        self.amountText = amountText
        self.currencyCode = currencyCode
        self.zeroConfirmed = zeroConfirmed
    }

    init(cost: PurchaseCost?, fallbackCurrency: String, locale: Locale = .current) {
        currencyCode = cost?.currencyCode ?? fallbackCurrency
        if let cost {
            zeroConfirmed = cost.amount == 0
            amountText = cost.amount == 0 ? "" : CostRules.format(cost.amount, locale: locale)
        }
    }
}

enum CostRules {
    /// Nil means Unknown. Throws when the input is ambiguous or out of range.
    static func parse(_ input: CostInput, locale: Locale = .current) throws -> PurchaseCost? {
        let currency = input.currencyCode.trimmed.uppercased()
        let text = input.amountText.trimmed

        if text.isEmpty {
            guard input.zeroConfirmed else { return nil }
            try validateCurrency(currency)
            return PurchaseCost(amount: 0, currencyCode: currency)
        }

        guard let amount = decimal(from: text, locale: locale) else {
            throw DomainError("Enter the purchase cost as a number, for example 129.90.")
        }
        guard amount >= 0 else { throw DomainError("Purchase cost cannot be negative.") }
        guard amount <= Limits.costMax else { throw DomainError("Purchase cost is too large.") }
        var rounded = amount
        var source = amount
        NSDecimalRound(&rounded, &source, 2, .plain)
        guard rounded == amount else { throw DomainError("Use at most two decimal places for the purchase cost.") }
        if amount == 0 && !input.zeroConfirmed {
            throw DomainError("To record a zero cost, use Enter Zero. Leave the field empty if the cost is unknown.")
        }
        try validateCurrency(currency)
        return PurchaseCost(amount: amount, currencyCode: currency)
    }

    static func validateCurrency(_ code: String) throws {
        let letters = CharacterSet.uppercaseLetters
        guard code.count == 3, code.unicodeScalars.allSatisfy({ letters.contains($0) && $0.isASCII }) else {
            throw DomainError("Choose a three-letter currency code, for example EUR.")
        }
    }

    /// Accepts either decimal separator and ignores grouping spaces.
    static func decimal(from text: String, locale: Locale) -> Decimal? {
        var cleaned = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        if separator != grouping, cleaned.contains(separator), cleaned.contains(grouping) {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard cleaned.filter({ $0 == "." }).count <= 1,
              cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }),
              !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func format(_ amount: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
