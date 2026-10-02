import SwiftUI

/// Three full-screen pages. Nothing is created here — no sample tools, no invented
/// workshop value; Skip and Get Started both lead to an empty Home.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        let asset: String
        let title: String
        let message: String
        let footnote: String?
    }

    private let pages = [
        Page(asset: "ck01_onboarding_catalogue", title: "Give Every Tool a Place",
             message: "Keep your tools, quantities, and storage together.", footnote: nil),
        Page(asset: "ck02_onboarding_prepare", title: "Build the Kit Before You Begin",
             message: "Check what is available before taking it out.", footnote: nil),
        Page(asset: "ck03_onboarding_return", title: "Know What Still Needs to Come Back",
             message: "Record each return and what needs attention.",
             footnote: "Copper Kit is your own log. It never messages the people you lend to and never confirms a return for them."),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [CK.Palette.deepBlue.opacity(0), CK.Palette.deepBlue.opacity(0.78), CK.Palette.deepBlue.opacity(0.94)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.5 + proxy.safeAreaInsets.bottom)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

                textZone(pages[page])
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            // The art is a background layer so its size can never push the text or buttons off screen.
            .background(background.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                if page < pages.count - 1 {
                    Button("Skip") { onFinish() }
                        .buttonStyle(CKTextButtonStyle(color: CK.Palette.cream))
                        .padding(.horizontal, CK.Space.m)
                        .background(Capsule().fill(CK.Palette.deepBlue.opacity(0.55)).padding(.vertical, 6))
                        .padding(.trailing, CK.Space.s)
                        .accessibilityHint("Goes straight to Home")
                }
            }
            .gesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    if value.translation.width < -60 { go(page + 1) }
                    if value.translation.width > 60 { go(page - 1) }
                }
            )
        }
        .statusBar(hidden: true)
    }

    /// Full-bleed art pinned to the top; the calm lower 40 % of each image sits behind the text.
    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                CK.Palette.deepBlue
                ForEach(pages.indices, id: \.self) { index in
                    if index == page, UIImage(named: pages[index].asset) != nil {
                        Image(pages[index].asset)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            .clipped()
                            .transition(.opacity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func textZone(_ current: Page) -> some View {
        VStack(alignment: .leading, spacing: CK.Space.s) {
            progress

            Text(current.title)
                .font(CKFont.display)
                .foregroundColor(CK.Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .id("title\(page)")

            Text(current.message)
                .font(CKFont.title3.weight(.regular))
                .foregroundColor(CK.Palette.cream.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if let footnote = current.footnote {
                Text(footnote)
                    .font(CKFont.footnote)
                    .foregroundColor(CK.Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: CK.Space.s) {
                if page > 0 {
                    Button("Back") { go(page - 1) }
                        .buttonStyle(OnboardingBackStyle())
                        .frame(maxWidth: 120)
                }
                Button(page == pages.count - 1 ? "Get Started" : "Next") {
                    if page == pages.count - 1 { onFinish() } else { go(page + 1) }
                }
                .buttonStyle(CKPrimaryButtonStyle())
            }
            .padding(.top, CK.Space.s)
        }
        .padding(.horizontal, CK.Space.l)
        .padding(.bottom, CK.Space.m)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)
    }

    private var progress: some View {
        HStack(spacing: CK.Space.xs) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? CK.Palette.gold : CK.Palette.cream.opacity(0.25))
                    .frame(width: index == page ? 28 : 14, height: 5)
            }
            Text("\(page + 1)/\(pages.count)")
                .font(CKFont.footnote.weight(.semibold).monospacedDigit())
                .foregroundColor(CK.Palette.cream.opacity(0.85))
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
    }

    private func go(_ target: Int) {
        guard pages.indices.contains(target) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.35)) {
            page = target
        }
    }
}

/// Back on the dark onboarding ground: cream outline, cream text.
private struct OnboardingBackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CKFont.button)
            .foregroundColor(CK.Palette.cream)
            .frame(maxWidth: .infinity, minHeight: CK.Size.button)
            .overlay(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .strokeBorder(CK.Palette.cream.opacity(0.7), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
