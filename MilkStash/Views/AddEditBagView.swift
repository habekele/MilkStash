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
            Form {
                // Ziplock contents
                Section {
                    // Unit picker on its own line
                    HStack {
                        Text("Unit")
                            .foregroundStyle(Color.ffInk2)
                        Spacer()
                        Picker("Unit", selection: $vm.unit) {
                            ForEach(MilkUnit.allCases, id: \.self) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }

                    // Quick presets in a scrollable row so they never wrap
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Quick:")
                                .font(.caption)
                                .foregroundStyle(Color.ffInk2)
                            ForEach([2.0, 3.0, 4.0, 5.0, 6.0], id: \.self) { preset in
                                Button {
                                    vm.volumePerBagText = String(format: "%.0f", preset)
                                } label: {
                                    Text("\(Int(preset)) \(vm.unit.rawValue)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.milkCoral.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.milkCoral)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    // Volume per bag
                    HStack {
                        Text("Volume per bag")
                            .foregroundStyle(Color.ffInk2)
                        Spacer()
                        TextField("0", text: $vm.volumePerBagText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .volumePerBag)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .frame(width: 80)
                        Text(vm.unit.rawValue)
                            .foregroundStyle(Color.ffInk2)
                    }

                    // Count of milk bags in this Ziplock
                    HStack {
                        Text("Milk bags in Ziplock")
                            .foregroundStyle(Color.ffInk2)
                        Spacer()
                        // Stepper + text field combo
                        HStack(spacing: 8) {
                            Button {
                                let c = max(1, (Int(vm.milkBagCountText) ?? 1) - 1)
                                vm.milkBagCountText = "\(c)"
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.milkCoral)
                            }
                            .buttonStyle(.plain)

                            TextField("1", text: $vm.milkBagCountText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .count)
                                .multilineTextAlignment(.center)
                                .font(.body.weight(.bold))
                                .frame(width: 44)

                            Button {
                                let c = (Int(vm.milkBagCountText) ?? 0) + 1
                                vm.milkBagCountText = "\(c)"
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.milkCoral)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Computed total
                    if vm.computedTotalOz > 0 {
                        HStack {
                            Text("Total in Ziplock")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(UnitConversion.formatted(vm.computedTotalOz, in: vm.unit))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.milkCoral)
                        }
                        .listRowBackground(Color.milkCoral.opacity(0.06))
                    }

                    if let err = vm.validationError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.milkDanger)
                    }
                } header: {
                    Text("Ziplock Contents")
                }

                // Dates
                Section("Dates") {
                    DatePicker("Freeze Date", selection: $vm.freezeDate, displayedComponents: .date)
                        .onChange(of: vm.freezeDate) {
                            vm.updateExpirationIfNeeded(settings: appSettings)
                        }

                    Toggle("Custom Expiration", isOn: $vm.useCustomExpiration)

                    if vm.useCustomExpiration {
                        DatePicker("Expiration Date", selection: $vm.expirationDate, displayedComponents: .date)
                    } else {
                        HStack {
                            Text("Expiration")
                                .foregroundStyle(Color.ffInk2)
                            Spacer()
                            Text(DateFormatter.freeze.string(from: computedExpiration))
                                .foregroundStyle(Color.ffInk2)
                        }
                    }
                }

                // Location with smart picker
                Section("Location") {
                    if knownLocations.isEmpty {
                        TextField("Location (e.g. Deep Freezer)", text: $vm.location)
                            .focused($focusedField, equals: .location)
                    } else {
                        HStack {
                            TextField("Location", text: $vm.location)
                                .focused($focusedField, equals: .location)
                            Menu {
                                ForEach(knownLocations, id: \.self) { loc in
                                    Button(loc) { vm.location = loc }
                                }
                                Divider()
                                Button("Clear") { vm.location = "" }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.milkCoral)
                                    .padding(6)
                                    .background(Color.milkCoral.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    if knownBins.isEmpty {
                        TextField("Bin / Slot (optional)", text: $vm.slotBin)
                            .focused($focusedField, equals: .bin)
                    } else {
                        HStack {
                            TextField("Bin / Slot", text: $vm.slotBin)
                                .focused($focusedField, equals: .bin)
                            Menu {
                                ForEach(knownBins, id: \.self) { bin in
                                    Button(bin) { vm.slotBin = bin }
                                }
                                Divider()
                                Button("Clear") { vm.slotBin = "" }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.milkCoral)
                                    .padding(6)
                                    .background(Color.milkCoral.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                // Optional details
                Section("Optional Details") {
                    TextField("Label Code", text: $vm.labelCode)
                        .focused($focusedField, equals: .label)
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }

                if isEditing {
                    Section("Status") {
                        Picker("Status", selection: $vm.status) {
                            ForEach(BagStatus.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Ziplock" : "Add Ziplock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
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
