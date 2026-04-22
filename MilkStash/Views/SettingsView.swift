// SettingsView.swift

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var context

    // Always work with a real persisted settings object
    private var appSettings: AppSettings {
        // Always return the same persisted object — never a throwaway
        if let s = settings.first { return s }
        let s = AppSettings()
        context.insert(s)
        try? context.save()
        return s
    }

    // Use this when writing to guarantee we hit the persisted record
    private func persistedSettings() -> AppSettings {
        if let s = settings.first { return s }
        let s = AppSettings()
        context.insert(s)
        try? context.save()
        return s
    }

    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var thresholdText: String = ""
    @State private var dailyOzText: String   = ""
    @FocusState private var focusThreshold: Bool
    @FocusState private var focusDailyOz: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Preferred Unit", selection: Binding(
                        get: { appSettings.preferredUnit },
                        set: { appSettings.preferredUnit = $0; try? context.save() }
                    )) {
                        ForEach(MilkUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Appearance", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Expiration") {
                    Picker("Default Shelf Life", selection: Binding(
                        get: { appSettings.defaultExpirationMonths },
                        set: { appSettings.defaultExpirationMonths = $0; try? context.save() }
                    )) {
                        Text("3 months").tag(3)
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    HStack {
                        Text("Low Stash Alert")
                        Spacer()
                        TextField("100", text: $thresholdText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusThreshold)
                            .frame(width: 80)
                            .onChange(of: thresholdText) {
                                if let val = Double(thresholdText), val > 0 {
                                    persistedSettings().lowStashThresholdOz = val
                                    try? context.save()
                                }
                            }
                        Text(appSettings.preferredUnit.rawValue).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Thresholds")
                } footer: {
                    Text("A warning appears on the home screen when your stash drops below this amount.")
                }

                Section {
                    HStack {
                        Text("Daily consumption")
                        Spacer()
                        TextField("25", text: $dailyOzText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusDailyOz)
                            .frame(width: 60)
                            .onChange(of: dailyOzText) {
                                if let val = Double(dailyOzText), val > 0 {
                                    persistedSettings().dailyOzGoal = val
                                    try? context.save()
                                }
                            }
                        Text("\(appSettings.preferredUnit.rawValue)/day").foregroundStyle(.secondary)
                    }

                    // Live preview of the formula
                    HStack {
                        Text("Days worth formula")
                            .foregroundStyle(.secondary)
                        Spacer()
                        let goal = Double(dailyOzText) ?? appSettings.dailyOzGoal
                        Text("total oz ÷ \(String(format: "%.0f", max(goal, 1)))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.milkIndigo)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Days Worth")
                } footer: {
                    Text("How many oz your baby drinks per day. Used to calculate how long your stash will last.")
                }

                Section("FIFO Options") {
                    Toggle("Include Expired by Default", isOn: Binding(
                        get: { appSettings.includeExpiredInFIFO },
                        set: { appSettings.includeExpiredInFIFO = $0; try? context.save() }
                    ))
                }

                Section("About") {
                    HStack {
                        Text("Unit Conversion")
                        Spacer()
                        Text("1 oz = 29.5735 mL")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                thresholdText = String(format: "%.0f", appSettings.lowStashThresholdOz)
                dailyOzText   = String(format: "%.0f", appSettings.dailyOzGoal)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusThreshold = false
                        focusDailyOz   = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
