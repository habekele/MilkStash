// SettingsView.swift

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var context

    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @discardableResult
    private func mutateSettings(_ block: (AppSettings) -> Void) -> AppSettings {
        let s: AppSettings
        if let existing = settings.first {
            s = existing
        } else {
            s = AppSettings()
            context.insert(s)
        }
        block(s)
        do { try context.save() } catch { print("SettingsView: save failed:", error) }
        return s
    }

    private func refreshEditableText(using settings: AppSettings) {
        thresholdText = String(format: "%.0f", settings.lowStashThresholdDisplayValue)
        dailyOzText   = String(format: "%.0f", settings.dailyGoalDisplayValue)
    }

    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var thresholdText: String = ""
    @State private var dailyOzText: String   = ""
    @FocusState private var focusThreshold: Bool
    @FocusState private var focusDailyOz: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    headerArea
                    displaySection
                    expirationSection
                    babySection
                    fifoSection
                    aboutSection
                    footerText
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 80)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .tracksTabBar()
            .navigationBarHidden(true)
            .onAppear {
                refreshEditableText(using: appSettings)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusThreshold = false
                        focusDailyOz   = false
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .foregroundStyle(Color.ffTerra)
                }
            }
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFEyebrow(text: "MAKE IT YOURS")
            Text("Settings")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Display Section

    private var displaySection: some View {
        settingsSection(title: "DISPLAY") {
            // Unit picker
            settingsRow {
                settingsLabel(icon: "ruler", label: "Unit")
            } value: {
                Picker("Unit", selection: Binding(
                    get: { appSettings.preferredUnit },
                    set: { v in
                        let updated = mutateSettings {
                            $0.preferredUnit = v
                        }
                        refreshEditableText(using: updated)
                    }
                )) {
                    ForEach(MilkUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .tint(Color.ffTerra)
            }

            // Appearance picker
            settingsRow {
                settingsLabel(icon: "circle.lefthalf.filled", label: "Appearance")
            } value: {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("Auto").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

    // MARK: - Expiration Section

    private var expirationSection: some View {
        settingsSection(title: "EXPIRATION") {
            VStack(spacing: 0) {
                ForEach([3, 6, 12], id: \.self) { months in
                    let isSelected = appSettings.defaultExpirationMonths == months
                    Button {
                        mutateSettings { $0.defaultExpirationMonths = months }
                    } label: {
                        HStack {
                            Text("\(months) months")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.ffInk)
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(isSelected ? Color.ffTerra : Color.ffLine, lineWidth: 2)
                                    .frame(width: 20, height: 20)
                                if isSelected {
                                    Circle()
                                        .fill(Color.ffTerra)
                                        .frame(width: 11, height: 11)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if months != 12 {
                        FFDivider()
                    }
                }
            }
        }
    }

    // MARK: - Baby Section

    private var babySection: some View {
        settingsSection(title: "YOUR BABY") {
            VStack(spacing: 0) {
                babyRow(
                    icon: "drop.fill",
                    label: "Daily intake",
                    unit: appSettings.preferredUnit.rawValue + "/day"
                ) {
                    TextField("25", text: $dailyOzText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusDailyOz)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ffTerra)
                        .monospacedDigit()
                        .fixedSize()
                        .onChange(of: dailyOzText) {
                            if let val = Double(dailyOzText), val > 0 {
                                mutateSettings { $0.setDailyGoalFromDisplayValue(val) }
                            }
                        }
                }

                babyRow(
                    icon: "exclamationmark.triangle",
                    label: "Low stash alert",
                    unit: appSettings.preferredUnit.rawValue
                ) {
                    TextField("100", text: $thresholdText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusThreshold)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ffTerra)
                        .monospacedDigit()
                        .fixedSize()
                        .onChange(of: thresholdText) {
                            if let val = Double(thresholdText), val > 0 {
                                mutateSettings { $0.setLowStashThresholdFromDisplayValue(val) }
                            }
                        }
                }

                babyRow(
                    icon: "target",
                    label: "Goal duration",
                    unit: "months"
                ) {
                    Text("\(appSettings.goalMonths)")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ffTerra)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func babyRow<Value: View>(
        icon: String,
        label: String,
        unit: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ffInk3)
                    .frame(width: 20)
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ffInk)
                    Text("(\(unit))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }
            }
            Spacer(minLength: 8)
            value()
        }
        .padding(.vertical, 10)
    }

    // MARK: - FIFO Section

    private var fifoSection: some View {
        settingsSection(title: "FIFO OPTIONS") {
            Toggle(isOn: Binding(
                get: { appSettings.includeExpiredInFIFO },
                set: { v in mutateSettings { $0.includeExpiredInFIFO = v } }
            )) {
                settingsLabel(icon: "clock.arrow.circlepath", label: "Include expired in FIFO")
            }
            .tint(Color.ffTerra)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        settingsSection(title: "ABOUT") {
            settingsRow {
                settingsLabel(icon: "arrow.left.arrow.right", label: "Unit conversion")
            } value: {
                Text("1 oz = 29.57 mL")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
                    .multilineTextAlignment(.trailing)
            }


            settingsRow {
                settingsLabel(icon: "info.circle", label: "App version")
            } value: {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Footer

    private var footerText: some View {
        Text("FreezeFlow v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · Made with care")
            .font(.system(size: 12))
            .foregroundStyle(Color.ffInk4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: title)
            FFCard(padding: 12) {
                content()
            }
        }
    }

    private func settingsRow<Label: View, Value: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
            value()
                .frame(alignment: .trailing)
        }
    }

    private func settingsLabel(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.ffInk)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
