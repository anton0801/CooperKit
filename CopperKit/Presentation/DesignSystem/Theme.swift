import SwiftUI
import UIKit

/// Copper Kit's colour, spacing and shape tokens. Screens never name a hex value or a
/// raw corner radius — they use these.
enum CK {
    enum Palette {
        /// Primary CTA, polished metal, small highlights.
        static let gold = Color(hex: 0xFFD24C)
        /// Rims, outlines and object accents.
        static let copper = Color(hex: 0xB46A32)
        /// Decorative inserts and the In Use state.
        static let amber = Color(hex: 0xFF9B2F)
        /// Hero and the main case.
        static let deepBlue = Color(hex: 0x111E3D)
        /// Inner lining and dark panels.
        static let velvet = Color(hex: 0x263C68)
        /// Secondary CTA and light inserts; text on dark.
        static let cream = Color(hex: 0xFFF4D8)

        /// The working background — strictly this value.
        static let background = Color(hex: 0xF8F3E9)
        static let surface = Color(hex: 0xFFFCF6)
        static let surfaceSunken = Color(hex: 0xF1EADB)
        static let ink = Color(hex: 0x242D43)
        static let inkSecondary = Color(hex: 0x657087)
        static let hairline = Color(hex: 0xB46A32).opacity(0.18)

        static let available = Color(hex: 0x23775A)
        static let returned = Color(hex: 0x23775A)
        static let needsService = Color(hex: 0x965D28)
        static let overdue = Color(hex: 0xB43A42)
        static let inUse = amber
        static let onLoan = velvet
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let hero: CGFloat = 22
        static let control: CGFloat = 14
        static let chip: CGFloat = 10
        static let thumb: CGFloat = 12
    }

    enum Size {
        /// Every tappable control is at least this tall.
        static let button: CGFloat = 48
        static let field: CGFloat = 50
        static let thumb: CGFloat = 56
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Global UIKit appearance so system navigation bars, pickers and alerts sit inside the
/// same palette as the SwiftUI screens.
enum CKAppearance {
    static func apply() {
        let ink = UIColor(hex: 0x242D43)
        let background = UIColor(hex: 0xF8F3E9)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = background
        bar.shadowColor = UIColor(hex: 0xB46A32).withAlphaComponent(0.18)
        bar.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont.systemFont(ofSize: 34, weight: .bold)),
        ]
        bar.titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .semibold)),
        ]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().tintColor = UIColor(hex: 0x263C68)

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(hex: 0xFFD24C)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(hex: 0x657087)], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor(hex: 0xF1EADB)

        UITextView.appearance().backgroundColor = .clear
        // Sections use a system TabView for state and accessibility, drawn with Copper
        // Kit's own bar instead of the system one.
        UITabBar.appearance().isHidden = true
    }
}
