// SettingsView.swift

import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct SettingsView: View {
    /// Jumps to the Journey tab, where the goal is actually edited.
    var onEditGoal: (() -> Void)? = nil

    @Query private var settings: [AppSettings]
    @Query private var allBags: [MilkBag]
    @Query(sort: \UsageEvent.timestamp, order: .reverse) private var events: [UsageEvent]
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
                .font(.ff(size: 34, weight: .regular, design: .serif))
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
                                .font(.ff(size: 15))
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
                        .font(.ff(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ffTerra)
                        .monospacedDigit()
                        .fixedSize()
                        .onChange(of: focusDailyOz) { _, focused in
                            if !focused { commitDailyGoal() }
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
                        .font(.ff(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ffTerra)
                        .monospacedDigit()
                        .fixedSize()
                        .onChange(of: focusThreshold) { _, focused in
                            if !focused { commitThreshold() }
                        }
                }

                babyRow(
                    icon: "target",
                    label: "Goal duration",
                    unit: "months"
                ) {
                    Button {
                        onEditGoal?()
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(appSettings.goalMonths)")
                                .font(.ff(size: 17, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.ffTerra)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.ff(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ffInk3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onEditGoal == nil)
                    .accessibilityHint("Opens the Journey tab to change your goal")
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
                    .font(.ff(size: 14))
                    .foregroundStyle(Color.ffInk3)
                    .frame(width: 20)
                HStack(spacing: 6) {
                    Text(label)
                        .font(.ff(size: 15))
                        .foregroundStyle(Color.ffInk)
                    Text("(\(unit))")
                        .font(.ff(size: 12, design: .monospaced))
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
                    .font(.ff(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
                    .multilineTextAlignment(.trailing)
            }


            ShareLink(item: CSVExport(text: stashCSV()),
                      preview: SharePreview("FreezeFlow stash export")) {
                HStack {
                    settingsLabel(icon: "square.and.arrow.up", label: "Export stash (CSV)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ff(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ffInk3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            ShareLink(item: CSVExport(text: historyCSV()),
                      preview: SharePreview("FreezeFlow history export")) {
                HStack {
                    settingsLabel(icon: "square.and.arrow.up", label: "Export history (CSV)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ff(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ffInk3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            settingsRow {
                settingsLabel(icon: "info.circle", label: "App version")
            } value: {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.ff(size: 14, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Footer

    private var footerText: some View {
        Text("FreezeFlow v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · Made with care")
            .font(.ff(size: 12))
            .foregroundStyle(Color.ffInk4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - Commit edits (on focus loss, not per keystroke)

    private func commitDailyGoal() {
        if let val = NumberParsing.double(from: dailyOzText), val > 0 {
            let updated = mutateSettings { $0.setDailyGoalFromDisplayValue(val) }
            refreshEditableText(using: updated)
        } else {
            refreshEditableText(using: appSettings)
        }
    }

    private func commitThreshold() {
        if let val = NumberParsing.double(from: thresholdText), val > 0 {
            let updated = mutateSettings { $0.setLowStashThresholdFromDisplayValue(val) }
            refreshEditableText(using: updated)
        } else {
            refreshEditableText(using: appSettings)
        }
    }

    // MARK: - CSV export

    private func csvField(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func stashCSV() -> String {
        var rows = ["Freeze Date,Expiration,Status,Milk Bags,Oz per Bag,Total Oz,Location,Bin,Label,Notes"]
        for bag in allBags.sorted(by: { $0.freezeDate < $1.freezeDate }) {
            rows.append([
                DateFormatter.csvDay.string(from: bag.freezeDate),
                DateFormatter.csvDay.string(from: bag.expirationDate),
                bag.status.rawValue,
                "\(bag.milkBagCount)",
                String(format: "%.2f", bag.volumePerBagOz),
                String(format: "%.2f", bag.totalVolumeOz),
                csvField(bag.location),
                csvField(bag.slotBin),
                csvField(bag.labelCode),
                csvField(bag.notes),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func historyCSV() -> String {
        var rows = ["Date,Time,Kind,Bags,Total Oz,Notes"]
        for e in events {
            rows.append([
                DateFormatter.csvDay.string(from: e.timestamp),
                DateFormatter.historyTime.string(from: e.timestamp),
                e.kind.rawValue,
                "\(e.totalBags)",
                String(format: "%.2f", e.totalVolumeOz),
                csvField(e.notes),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
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
                .font(.ff(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)
            Text(label)
                .font(.ff(size: 15))
                .foregroundStyle(Color.ffInk)
        }
    }
}

/// Lazily-rendered CSV payload for ShareLink.
struct CSVExport: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.text.utf8)
        }
        .suggestedFileName("FreezeFlow-export.csv")
    }
}

extension DateFormatter {
    static let csvDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
