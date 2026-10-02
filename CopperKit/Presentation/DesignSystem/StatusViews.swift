import SwiftUI

/// The four places a unit can be. Every badge carries its words and an icon, so the
/// state is never told by colour alone.
enum UnitState: CaseIterable {
    case available, inUse, onLoan, needsService

    var title: String {
        switch self {
        case .available: return "Available"
        case .inUse: return "In Use"
        case .onLoan: return "On Loan"
        case .needsService: return "Needs Service"
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .inUse: return "hammer.fill"
        case .onLoan: return "person.fill"
        case .needsService: return "wrench.fill"
        }
    }

    var fill: Color {
        switch self {
        case .available: return CK.Palette.available
        case .inUse: return CK.Palette.inUse
        case .onLoan: return CK.Palette.onLoan
        case .needsService: return CK.Palette.needsService
        }
    }

    /// Text colour that passes contrast on `fill`.
    var onFill: Color {
        switch self {
        case .inUse: return CK.Palette.ink
        case .available, .onLoan, .needsService: return .white
        }
    }

    func count(in balance: ToolBalance) -> Int {
        switch self {
        case .available: return balance.available
        case .inUse: return balance.inUse
        case .onLoan: return balance.onLoan
        case .needsService: return balance.needsService
        }
    }
}

struct StatusBadge: View {
    let title: String
    let icon: String
    let fill: Color
    let textColor: Color

    init(_ state: UnitState, count: Int? = nil) {
        title = count.map { "\($0) \(state.title)" } ?? state.title
        icon = state.icon
        fill = state.fill
        textColor = state.onFill
    }

    init(handover status: HandoverStatus) {
        switch status {
        case .open:
            title = "Open"; icon = "clock.fill"; fill = CK.Palette.velvet; textColor = .white
        case .overdue:
            title = "Overdue"; icon = "exclamationmark.circle.fill"; fill = CK.Palette.overdue; textColor = .white
        case .returned:
            title = "Returned"; icon = "checkmark.seal.fill"; fill = CK.Palette.returned; textColor = .white
        }
    }

    init(title: String, icon: String, fill: Color, textColor: Color = .white) {
        self.title = title
        self.icon = icon
        self.fill = fill
        self.textColor = textColor
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(CKFont.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(title)
                .font(CKFont.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// A neutral outline tag (Archived, Out of Stock, Needs Review).
struct TagView: View {
    let text: String
    var icon: String?
    var color: Color = CK.Palette.inkSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(CKFont.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(CKFont.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The unit rack: one bar split into the four states in proportion, with a written
/// legend underneath. It is the same instrument on Home, the catalogue and the detail.
struct UnitRack: View {
    let balance: ToolBalance
    var showsLegend = true
    var height: CGFloat = 12

    private var segments: [(UnitState, Int)] {
        UnitState.allCases.map { ($0, $0.count(in: balance)) }.filter { $0.1 > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CK.Space.xs) {
            GeometryReader { proxy in
                let total = max(1, segments.reduce(0) { $0 + $1.1 })
                let gaps = CGFloat(max(0, segments.count - 1)) * 2
                HStack(spacing: 2) {
                    if segments.isEmpty {
                        Capsule().fill(CK.Palette.surfaceSunken)
                    } else {
                        ForEach(segments, id: \.0) { state, count in
                            Rectangle()
                                .fill(state.fill)
                                .frame(width: max(3, (proxy.size.width - gaps) * CGFloat(count) / CGFloat(total)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: height)
            .accessibilityHidden(true)

            if showsLegend {
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(UnitState.allCases, id: \.self) { state in
                HStack(spacing: 6) {
                    Image(systemName: state.icon)
                        .font(CKFont.caption.weight(.bold))
                        .foregroundColor(state == .inUse ? CK.Palette.copper : state.fill)
                        .frame(width: 16)
                    Text("\(state.count(in: balance))")
                        .font(CKFont.subhead.weight(.bold).monospacedDigit())
                        .foregroundColor(CK.Palette.ink)
                    Text(state.title)
                        .font(CKFont.subhead)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var accessibilityText: String {
        UnitState.allCases.map { "\($0.count(in: balance)) \($0.title)" }.joined(separator: ", ")
    }
}

/// The embossed brand mark: the abstract geometry of a tool handle — a grip with three
/// ridges and a ferrule ring. Drawn, never a letter. Fill it even-odd (`CaseMarkIcon`).
struct CaseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        // Grip body
        let grip = CGRect(x: rect.minX + w * 0.04, y: rect.minY + h * 0.22, width: w * 0.62, height: h * 0.56)
        path.addRoundedRect(in: grip, cornerSize: CGSize(width: h * 0.28, height: h * 0.28))
        // Ferrule ring
        let ring = CGRect(x: rect.minX + w * 0.68, y: rect.minY + h * 0.12, width: w * 0.1, height: h * 0.76)
        path.addRoundedRect(in: ring, cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
        // Shank
        let shank = CGRect(x: rect.minX + w * 0.8, y: rect.minY + h * 0.38, width: w * 0.2, height: h * 0.24)
        path.addRoundedRect(in: shank, cornerSize: CGSize(width: h * 0.08, height: h * 0.08))
        // Ridges cut into the grip
        var ridges = Path()
        for i in 0..<3 {
            let x = grip.minX + grip.width * (0.3 + CGFloat(i) * 0.2)
            ridges.addRoundedRect(in: CGRect(x: x, y: grip.minY + grip.height * 0.18, width: w * 0.035, height: grip.height * 0.64),
                                  cornerSize: CGSize(width: w * 0.015, height: w * 0.015))
        }
        // Ridges are separate sub-paths; filled even-odd they read as grooves.
        path.addPath(ridges)
        return path
    }
}

/// The mark filled correctly (even-odd, so the ridges are cut out).
struct CaseMarkIcon: View {
    var color: Color = CK.Palette.ink

    var body: some View {
        CaseMark()
            .fill(color, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }
}
