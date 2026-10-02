import SwiftUI

/// Gold with dark text — the one primary action on a screen.
struct CKPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CKFont.button)
            .multilineTextAlignment(.center)
            .foregroundColor(CK.Palette.ink.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, CK.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: CK.Size.button)
            .background(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .fill(isEnabled ? CK.Palette.gold : CK.Palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .strokeBorder(isEnabled ? CK.Palette.copper.opacity(0.55) : CK.Palette.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Cream with a copper outline.
struct CKSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CKFont.button)
            .multilineTextAlignment(.center)
            .foregroundColor(CK.Palette.ink.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, CK.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: CK.Size.button)
            .background(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .fill(CK.Palette.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .strokeBorder(CK.Palette.copper.opacity(isEnabled ? 1 : 0.35), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Text-only action, still 48 pt tall.
struct CKTextButtonStyle: ButtonStyle {
    var color: Color = CK.Palette.velvet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CKFont.button)
            .foregroundColor(color)
            .frame(minHeight: CK.Size.button)
            .padding(.horizontal, CK.Space.xs)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A destructive action set in the overdue red, always with words.
struct CKDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CKFont.button)
            .foregroundColor(CK.Palette.overdue.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: CK.Size.button)
            .background(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .strokeBorder(CK.Palette.overdue.opacity(isEnabled ? 0.6 : 0.2), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A square tile used on Home for the section shortcuts.
struct CKTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                    .fill(CK.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CK.Radius.card, style: .continuous)
                    .strokeBorder(CK.Palette.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// The "Home" control that sits at the top of every section.
struct HomeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CaseMarkIcon(color: CK.Palette.ink)
                    .frame(width: 18, height: 12)
                Text("Home")
                    .font(CKFont.subhead.weight(.semibold))
                    .foregroundColor(CK.Palette.ink)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Capsule().fill(CK.Palette.gold))
            .overlay(Capsule().strokeBorder(CK.Palette.copper.opacity(0.5), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
        .accessibilityHint("Shows the workshop summary")
    }
}
