import SwiftUI

/// The standard card: warm surface, 20 pt corners, copper hairline, a soft deep-blue
/// contact shadow. No glare — highlights belong to metal objects only.
struct CKCard<Content: View>: View {
    var padding: CGFloat = CK.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CK.Space.s) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                .fill(CK.Palette.surface)
                .shadow(color: CK.Palette.deepBlue.opacity(0.07), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                .strokeBorder(CK.Palette.hairline, lineWidth: 1)
        )
    }
}

/// Section title with a short copper rule after it.
struct CKSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CK.Space.xs) {
            Text(title)
                .font(CKFont.title3)
                .foregroundColor(CK.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(CK.Palette.copper.opacity(0.45))
                .frame(width: 28, height: 2)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 5 }
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, CK.Space.xs)
    }
}

extension CKSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        trailing = EmptyView()
    }
}

/// Screen scaffold: the working background and standard insets.
struct CKScroll<Content: View>: View {
    var spacing: CGFloat = CK.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, CK.Space.m)
            .padding(.top, CK.Space.xs)
            .padding(.bottom, CK.Space.xl)
        }
        .background(CK.Palette.background.ignoresSafeArea())
    }
}

/// A label/value line used on detail screens.
struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = CK.Palette.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CK.Space.s) {
            CKLabel(key)
            Spacer(minLength: CK.Space.xs)
            Text(value)
                .font(CKFont.body)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Thin copper divider.
struct CKDivider: View {
    var body: some View {
        Rectangle()
            .fill(CK.Palette.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A notice block for refusals and explanations. Always words, never colour alone.
struct NoticeView: View {
    enum Tone { case info, warning, error }

    let text: String
    var tone: Tone = .info

    private var color: Color {
        switch tone {
        case .info: return CK.Palette.velvet
        case .warning: return CK.Palette.needsService
        case .error: return CK.Palette.overdue
        }
    }

    private var icon: String {
        switch tone {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: CK.Space.s) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(CKFont.body)
                .accessibilityHidden(true)
            Text(text)
                .font(CKFont.subhead)
                .foregroundColor(CK.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(CK.Space.s)
        .background(
            RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                .fill(color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Empty state: at most one small sprite, a title, a sentence and an action.
struct EmptyStateView<Actions: View>: View {
    let asset: String?
    var assetSize = CGSize(width: 96, height: 96)
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: CK.Space.s) {
            if let asset {
                Sprite(asset, size: assetSize)
            }
            Text(title)
                .font(CKFont.title)
                .foregroundColor(CK.Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(CKFont.body)
                .foregroundColor(CK.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, CK.Space.xs)
        }
        .padding(.vertical, CK.Space.l)
        .padding(.horizontal, CK.Space.m)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(asset: String?, assetSize: CGSize = CGSize(width: 96, height: 96), title: String, message: String) {
        self.asset = asset
        self.assetSize = assetSize
        self.title = title
        self.message = message
        actions = EmptyView()
    }
}

/// One of the bundled illustrations. Decorative, so hidden from VoiceOver; when the
/// file is missing it quietly draws nothing rather than a broken image.
struct Sprite: View {
    let name: String
    let size: CGSize

    init(_ name: String, size: CGSize) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// A row that becomes a column at accessibility text sizes, so long words never split.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    var spacing: CGFloat = CK.Space.s
    @ViewBuilder var content: Content

    var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: .center, spacing: spacing) { content }
        }
    }
}
