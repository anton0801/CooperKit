import SwiftUI

/// The type scale. Everything is built on text styles so it grows with Dynamic Type:
/// SF Pro bold for titles, plain SF Pro for reading, stamped small-caps labels (like the
/// engraving on a brass plate) and heavy monospaced-digit figures so counts never jump.
enum CKFont {
    static let display = Font.system(.largeTitle).weight(.bold)
    static let title = Font.system(.title2).weight(.bold)
    static let title3 = Font.system(.title3).weight(.semibold)
    static let headline = Font.system(.headline)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let subhead = Font.system(.subheadline)
    static let footnote = Font.system(.footnote)
    static let caption = Font.system(.caption)
    static let button = Font.system(.body).weight(.semibold)
    static let label = Font.system(.footnote).weight(.semibold).lowercaseSmallCaps()
    static let smallFigure = Font.system(.title3).weight(.bold).monospacedDigit()
    static let rowFigure = Font.system(.title2).weight(.heavy).monospacedDigit()
}

/// A stamped label: small caps, slightly tracked.
struct CKLabel: View {
    let text: String
    var color: Color = CK.Palette.inkSecondary

    init(_ text: String, color: Color = CK.Palette.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(CKFont.label)
            .kerning(0.6)
            .foregroundColor(color)
    }
}

/// Large figures that still scale with Dynamic Type (`Font.system(size:)` alone does not).
struct CKFigure: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .largeTitle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight).monospacedDigit())
    }
}

extension View {
    func ckFigure(_ size: CGFloat, weight: Font.Weight = .heavy) -> some View {
        modifier(CKFigure(size: size, weight: weight))
    }
}
