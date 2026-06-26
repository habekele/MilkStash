// AddEditBagView.swift

import SwiftUI
import SwiftData

struct AddEditBagView: View {
    let bag: MilkBag?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @Query private var allBags: [MilkBag]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @State private var vm = AddEditBagViewModel()
    @FocusState private var focusedField: Field?

    enum Field { case volumePerBag, count, location, bin, label, notes }

    private var isEditing: Bool { bag != nil }

    private var knownLocations: [String] {
        Array(Set(allBags.map(\.location).filter { !$0.isEmpty })).sorted()
    }

    private var knownBins: [String] {
        Array(Set(allBags
            .filter { $0.location == vm.location && !$0.slotBin.isEmpty }
            .map(\.slotBin)
        )).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerArea
                    contentsSection
                    datesSection
                    locationSection
                    detailsSection
                    if isEditing { statusSection }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .foregroundStyle(Color.ffTerra)
                }
            }
        }
        .onAppear {
            vm.unit = appSettings.preferredUnit
            if let bag = bag {
                vm.load(from: bag, settings: appSettings)
            } else {
                vm.updateExpirationIfNeeded(settings: appSettings)
            }
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ffInk2)
                Spacer()
                Button(isEditing ? "Save" : "Add") { save() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.ffTerra, in: Capsule())
            }

            Text(isEditing ? "Edit Ziplock" : "New Ziplock")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Contents

    private var contentsSection: some View {
        themedSection(title: "ZIPLOCK CONTENTS") {
            VStack(spacing: 0) {
                // Unit
                row {
                    rowLabel(icon: "ruler", label: "Unit")
                } value: {
                    Picker("Unit", selection: $vm.unit) {
                        ForEach(MilkUnit.allCases, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    .tint(Color.ffTerra)
                }
                FFDivider()

                // Quick presets
                quickPresetsRow
                FFDivider()

                // Volume per bag
                row {
                    rowLabel(icon: "drop", label: "Volume per bag")
                } value: {
                    HStack(spacing: 6) {
                        TextField("0", text: $vm.volumePerBagText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .volumePerBag)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffTerra)
                            .frame(width: 60)
                        Text(vm.unit.rawValue)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                            .frame(width: 30, alignment: .leading)
                    }
                }
                FFDivider()

                // Bag count stepper
                row {
                    rowLabel(icon: "square.stack.3d.up", label: "Milk bags in Ziplock")
                } value: {
                    HStack(spacing: 8) {
                        Button {
                            let c = max(1, (Int(vm.milkBagCountText) ?? 1) - 1)
                            vm.milkBagCountText = "\(c)"
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.ffTerra)
                        }
                        .buttonStyle(.plain)

                        TextField("1", text: $vm.milkBagCountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .count)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ffInk)
                            .frame(width: 36)

                        Button {
                            let c = (Int(vm.milkBagCountText) ?? 0) + 1
                            vm.milkBagCountText = "\(c)"
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.ffTerra)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if vm.computedTotalOz > 0 {
                    HStack {
                        Text("Total in Ziplock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.ffInk2)
                        Spacer()
                        Text(UnitConversion.formatted(vm.computedTotalOz, in: vm.unit))
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffTerra)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: Radius.l))
                    .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.ffTerra.opacity(0.18), lineWidth: 0.5))
                    .padding(.top, 10)
                }

                if let err = vm.validationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(err)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.milkDanger)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var quickPresetsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ffInk3)
                Text("QUICK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.ffInk3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([2.0, 3.0, 4.0, 5.0, 6.0], id: \.self) { preset in
                        Button {
                            vm.volumePerBagText = String(format: "%.0f", preset)
                        } label: {
                            let isSelected = vm.volumePerBagText == String(format: "%.0f", preset)
                            Text("\(Int(preset)) \(vm.unit.rawValue)")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.ffTerra : Color.ffSurface2, in: Capsule())
                                .foregroundStyle(isSelected ? .white : Color.ffInk)
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.ffLine, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Dates

    private var datesSection: some View {
        themedSection(title: "DATES") {
            VStack(spacing: 0) {
                row {
                    rowLabel(icon: "snowflake", label: "Freeze date")
                } value: {
                    DatePicker("", selection: $vm.freezeDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.ffTerra)
                        .onChange(of: vm.freezeDate) {
                            vm.updateExpirationIfNeeded(settings: appSettings)
                        }
                }
                FFDivider()

                Toggle(isOn: $vm.useCustomExpiration) {
                    rowLabel(icon: "calendar.badge.clock", label: "Custom expiration")
                }
                .tint(Color.ffTerra)
                .padding(.vertical, 10)

                FFDivider()

                if vm.useCustomExpiration {
                    row {
                        rowLabel(icon: "hourglass", label: "Expires")
                    } value: {
                        DatePicker("", selection: $vm.expirationDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.ffTerra)
                    }
                } else {
                    row {
                        rowLabel(icon: "hourglass", label: "Expires")
                    } value: {
                        Text(DateFormatter.freeze.string(from: computedExpiration))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                    }
                }
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        themedSection(title: "LOCATION") {
            VStack(spacing: 0) {
                themedTextField(
                    icon: "tray.full",
                    placeholder: "Location (e.g. Deep Freezer)",
                    text: $vm.location,
                    field: .location,
                    suggestions: knownLocations,
                    onPick: { vm.location = $0 },
                    onClear: { vm.location = "" }
                )

                FFDivider()

                themedTextField(
                    icon: "square.grid.2x2",
                    placeholder: "Bin / Slot (optional)",
                    text: $vm.slotBin,
                    field: .bin,
                    suggestions: knownBins,
                    onPick: { vm.slotBin = $0 },
                    onClear: { vm.slotBin = "" }
                )
            }
        }
    }

    private func themedTextField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        suggestions: [String],
        onPick: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .font(.system(size: 15))
                .foregroundStyle(Color.ffInk)
                .tint(Color.ffTerra)

            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { onPick(s) }
                    }
                    Divider()
                    Button("Clear", role: .destructive, action: onClear)
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ffTerra)
                        .padding(6)
                        .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Optional Details

    private var detailsSection: some View {
        themedSection(title: "OPTIONAL DETAILS") {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ffInk3)
                        .frame(width: 20)
                    TextField("Label code", text: $vm.labelCode)
                        .focused($focusedField, equals: .label)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ffInk)
                        .tint(Color.ffTerra)
                }
                .padding(.vertical, 12)

                FFDivider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ffInk3)
                        .frame(width: 20)
                        .padding(.top, 4)
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ffInk)
                        .tint(Color.ffTerra)
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        themedSection(title: "STATUS") {
            Picker("Status", selection: $vm.status) {
                ForEach(BagStatus.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .tint(Color.ffTerra)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Layout helpers

    private func themedSection<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: title)
            FFCard(padding: 12) { content() }
        }
    }

    private func row<L: View, V: View>(
        @ViewBuilder label: () -> L,
        @ViewBuilder value: () -> V
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            label().frame(maxWidth: .infinity, alignment: .leading)
            value().frame(alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private func rowLabel(icon: String, label: String) -> some View {
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

    // MARK: - Logic

    private var computedExpiration: Date {
        StashService.expirationDate(from: vm.freezeDate, months: appSettings.defaultExpirationMonths)
    }

    private func save() {
        guard vm.validate() else { return }
        if vm.save(bag: bag, context: context, settings: appSettings) {
            dismiss()
        }
    }
}

#Preview {
    AddEditBagView(bag: nil)
        .modelContainer(PreviewData.container())
}
