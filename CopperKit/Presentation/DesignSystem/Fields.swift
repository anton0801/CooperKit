import SwiftUI

/// Label above, 50 pt field, optional helper line. Required fields carry an asterisk in
/// the label and say "required" to VoiceOver.
struct CKTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var required = false
    var helper: String?
    var limit: Int?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: required)
            TextField(placeholder, text: $text)
                .font(CKFont.body)
                .foregroundColor(CK.Palette.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .disableAutocorrection(keyboard != .default)
                .padding(.horizontal, CK.Space.s)
                .frame(minHeight: CK.Size.field)
                .background(FieldBackground())
                .accessibilityLabel(required ? "\(label), required" : label)
            FieldFooter(helper: helper, count: text.count, limit: limit)
        }
    }
}

/// Multi-line text with a character counter.
struct CKTextArea: View {
    let label: String
    @Binding var text: String
    var limit: Int
    var minHeight: CGFloat = 96
    var helper: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: false)
            TextEditor(text: $text)
                .font(CKFont.body)
                .foregroundColor(CK.Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: minHeight)
                .background(FieldBackground())
                .accessibilityLabel(label)
            FieldFooter(helper: helper, count: text.count, limit: limit)
        }
    }
}

struct FieldLabel: View {
    let label: String
    var required: Bool

    var body: some View {
        HStack(spacing: 2) {
            CKLabel(label)
            if required {
                Text("*")
                    .font(CKFont.footnote.weight(.bold))
                    .foregroundColor(CK.Palette.copper)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct FieldBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
            .fill(CK.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: CK.Radius.control, style: .continuous)
                    .strokeBorder(CK.Palette.copper.opacity(0.32), lineWidth: 1)
            )
    }
}

struct FieldFooter: View {
    var helper: String?
    var count: Int
    var limit: Int?

    var body: some View {
        if helper != nil || (limit.map { count > $0 * 8 / 10 } ?? false) {
            HStack(alignment: .top) {
                if let helper {
                    Text(helper)
                        .font(CKFont.caption)
                        .foregroundColor(CK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CK.Space.xs)
                if let limit, count > limit * 8 / 10 {
                    Text("\(count)/\(limit)")
                        .font(CKFont.caption.monospacedDigit())
                        .foregroundColor(count > limit ? CK.Palette.overdue : CK.Palette.inkSecondary)
                }
            }
        }
    }
}

/// A picker presented as a field-shaped menu.
struct CKMenuField<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var required = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label: label, required: required)
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(title(option)).tag(option)
                    }
                }
            } label: {
                HStack {
                    Text(title(selection))
                        .font(CKFont.body)
                        .foregroundColor(CK.Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(CKFont.footnote.weight(.semibold))
                        .foregroundColor(CK.Palette.copper)
                }
                .padding(.horizontal, CK.Space.s)
                .frame(minHeight: CK.Size.field)
                .background(FieldBackground())
            }
            .accessibilityLabel("\(label): \(title(selection))")
        }
    }
}

/// − n + with 48 pt targets, typed entry, and bounds that are stated rather than silent.
struct QuantityStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var label: String = "Quantity"
    var compact = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            .accessibilityLabel("Decrease \(label)")

            TextField("", text: $text)
                .font(CKFont.smallFigure)
                .foregroundColor(CK.Palette.ink)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .focused($focused)
                .frame(minWidth: compact ? 44 : 56, minHeight: CK.Size.button)
                .onChange(of: text) { newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                    if let number = Int(digits.prefix(4)) {
                        value = min(max(number, range.lowerBound), range.upperBound)
                    }
                }
                .onChange(of: focused) { isFocused in
                    if !isFocused { text = "\(value)" }
                }
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")

            stepButton(systemName: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
            .accessibilityLabel("Increase \(label)")
        }
        .background(FieldBackground())
        .fixedSize()
        .onAppear { text = "\(value)" }
        .onChange(of: value) { newValue in
            if !focused { text = "\(newValue)" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(CKFont.body.weight(.bold))
                .foregroundColor(enabled ? CK.Palette.ink : CK.Palette.inkSecondary.opacity(0.4))
                .frame(width: compact ? 44 : 48, height: CK.Size.button)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A checkbox that is a real button with a 48 pt target and a spoken state.
struct CheckBox: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? CK.Palette.gold : CK.Palette.surface)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? CK.Palette.copper : CK.Palette.inkSecondary.opacity(0.6), lineWidth: 1.5)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(CKFont.body.weight(.heavy))
                        .foregroundColor(CK.Palette.ink)
                }
            }
            .frame(width: 30, height: 30)
            .frame(width: CK.Size.button, height: CK.Size.button)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isButton)
    }
}

/// Segmented choice used for filters and modes.
struct CKSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 36)
    }
}

/// A toggle chip for simple filters ("Available Only").
struct FilterChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                    .font(CKFont.footnote.weight(.bold))
                Text(title)
                    .font(CKFont.subhead.weight(.semibold))
            }
            .foregroundColor(CK.Palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule().fill(isOn ? CK.Palette.gold : CK.Palette.surface))
            .overlay(Capsule().strokeBorder(isOn ? CK.Palette.copper.opacity(0.6) : CK.Palette.hairline, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
