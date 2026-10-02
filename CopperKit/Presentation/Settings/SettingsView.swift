import SwiftUI

/// Settings: defaults for new records, owner-only reminders, export and Delete All Data.
struct SettingsView: View {
    @EnvironmentObject private var store: WorkshopStore
    @EnvironmentObject private var router: AppRouter
    @AppStorage("ck.onboardingDone") private var onboardingDone = true

    @State private var share: SharePayload?
    @State private var confirmingDelete = false
    @State private var deleteText = ""
    @State private var remindersDenied = false

    var body: some View {
        let settings = store.workshop.settings
        CKScroll {
            CKSectionHeader("Defaults")
            CKCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Loan Length").font(CKFont.headline).foregroundColor(CK.Palette.ink)
                        Text("Pre-fills Due At on a new checkout.").font(CKFont.caption).foregroundColor(CK.Palette.inkSecondary)
                    }
                    Spacer()
                    QuantityStepper(value: Binding(
                        get: { settings.defaultLoanDays },
                        set: { value in var s = settings; s.defaultLoanDays = value; _ = store.updateSettings(s) }
                    ), range: Limits.loanDays, label: "Default loan length in days", compact: true)
                }
                Text("\(settings.defaultLoanDays) \(settings.defaultLoanDays == 1 ? "day" : "days")")
                    .font(CKFont.footnote.monospacedDigit())
                    .foregroundColor(CK.Palette.inkSecondary)
                CKDivider()
                CKMenuField(label: "Default Currency", selection: Binding(
                    get: { settings.defaultCurrencyCode },
                    set: { value in var s = settings; s.defaultCurrencyCode = value; _ = store.updateSettings(s) }
                ), options: Currencies.all(including: settings.defaultCurrencyCode), title: { $0 })
                Text("Used when you enter a private purchase cost. Amounts are never converted or totalled.")
                    .font(CKFont.caption)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CKSectionHeader("Reminders")
            CKCard {
                Toggle(isOn: Binding(
                    get: { settings.dueRemindersEnabled },
                    set: { value in
                        if value {
                            store.requestReminderPermission { granted in
                                var s = store.workshop.settings
                                s.dueRemindersEnabled = granted
                                _ = store.updateSettings(s)
                                remindersDenied = !granted
                            }
                        } else {
                            var s = settings
                            s.dueRemindersEnabled = false
                            _ = store.updateSettings(s)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Due Date Reminders").font(CKFont.headline).foregroundColor(CK.Palette.ink)
                        Text("A notification on this device when a handover is due. Nobody else is contacted.")
                            .font(CKFont.caption)
                            .foregroundColor(CK.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(CK.Palette.copper)
                if remindersDenied {
                    NoticeView(text: "Notifications are off for Copper Kit. You can allow them in Settings.", tone: .warning)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(CKTextButtonStyle())
                }
            }

            CKSectionHeader("Your Data")
            CKCard {
                Text("Everything stays on this device. Copper Kit has no account, no cloud and no analytics, and it never sends anything to the people you lend to.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { export(tools: true) } label: { Label("Export Tools (CSV)", systemImage: "square.and.arrow.up") }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(store.workshop.tools.isEmpty)
                Button { export(tools: false) } label: { Label("Export Handovers (CSV)", systemImage: "square.and.arrow.up") }
                    .buttonStyle(CKSecondaryButtonStyle())
                    .disabled(store.workshop.handovers.isEmpty)
            }

            CKSectionHeader("About")
            CKCard {
                Button("Show Onboarding Again") { onboardingDone = false }
                    .buttonStyle(CKTextButtonStyle())
                KeyValueRow(key: "version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }

            CKSectionHeader("Danger Zone")
            VStack(alignment: .leading, spacing: CK.Space.xs) {
                Text("Delete All Data removes every tool, photo, location, kit, handover, service record and the history. It can't be undone.")
                    .font(CKFont.subhead)
                    .foregroundColor(CK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if confirmingDelete {
                    CKTextField(label: "Type DELETE to confirm", text: $deleteText, placeholder: "DELETE", capitalization: .characters)
                    HStack(spacing: CK.Space.s) {
                        Button("Cancel") { confirmingDelete = false; deleteText = "" }
                            .buttonStyle(CKSecondaryButtonStyle())
                        Button("Delete Everything") {
                            if store.deleteAllData() {
                                confirmingDelete = false
                                deleteText = ""
                                store.showToast("All data deleted")
                            }
                        }
                        .buttonStyle(CKDestructiveButtonStyle())
                        .disabled(deleteText.trimmed != "DELETE")
                    }
                } else {
                    Button("Delete All Data") { confirmingDelete = true }
                        .buttonStyle(CKDestructiveButtonStyle())
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items).ignoresSafeArea()
        }
    }

    private func export(tools: Bool) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let text = tools ? WorkshopExport.toolsCSV(store.workshop) : WorkshopExport.handoversCSV(store.workshop, now: store.now)
        let name = tools ? "CopperKit-Tools-\(stamp).csv" : "CopperKit-Handovers-\(stamp).csv"
        if let url = TemporaryExport.file(named: name, contents: text) {
            share = SharePayload(items: [url])
        } else {
            store.alert = AlertMessage(title: "Export Failed", message: "The file could not be prepared. Try again.")
        }
    }
}
