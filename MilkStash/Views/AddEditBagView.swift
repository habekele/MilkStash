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
    @State private var showDeleteConfirm = false
    @State private var showMore = false

    // Brief confirmation shown after a save, before the sheet dismisses.
    @State private var savedSummary: (oz: Double, bags: Int)? = nil

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
                    freezeDateSection
                    moreDetailsSection
                    if isEditing {
                        statusSection
                        deleteButton
                    } else {
                        saveAndAddAnotherButton
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .overlay {
                if let s = savedSummary {
                    savedOverlay(oz: s.oz, bags: s.bags)
                }
            }
            .alert("Delete Brick?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteBag() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes this Brick from your stash. This can't be undone.")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .foregroundStyle(Color.ffTerra)
                }
            }
        }
        .onAppear {
            Haptics.prepare()
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
                    .font(.ff(size: 16))
                    .foregroundStyle(Color.ffInk2)
                Spacer()
                Button(isEditing ? "Save" : "Add") { save() }
                    .font(.ff(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.ffTerra.opacity(vm.isValid ? 1 : 0.45), in: Capsule())
                    .disabled(!vm.isValid)
            }

            Text(isEditing ? "Edit Brick" : "New Brick")
                .font(.ff(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Contents

    private var contentsSection: some View {
        themedSection(title: "BRICK CONTENTS") {
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
                    .onChange(of: vm.unit) { Haptics.light() }
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
                            .font(.ff(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffTerra)
                            .frame(width: 60)
                        Text(vm.unit.rawValue)
                            .font(.ff(size: 12, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                            .frame(width: 30, alignment: .leading)
                    }
                }
                FFDivider()

                // Bag count stepper
                row {
                    rowLabel(icon: "square.stack.3d.up", label: "Milk bags in Brick")
                } value: {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.light()
                            let c = max(1, (Int(vm.milkBagCountText) ?? 1) - 1)
                            vm.milkBagCountText = "\(c)"
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.ffTerra)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove a bag")

                        TextField("1", text: $vm.milkBagCountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .count)
                            .multilineTextAlignment(.center)
                            .font(.ff(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ffInk)
                            .frame(width: 36)

                        Button {
                            Haptics.light()
                            let c = (Int(vm.milkBagCountText) ?? 0) + 1
                            vm.milkBagCountText = "\(c)"
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.ffTerra)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a bag")
                    }
                }

                if vm.computedTotalOz > 0 {
                    HStack {
                        Text("Total in Brick")
                            .font(.ff(size: 13, weight: .medium))
                            .foregroundStyle(Color.ffInk2)
                        Spacer()
                        Text(UnitConversion.formatted(vm.computedTotalOz, in: vm.unit))
                            .font(.ff(size: 17, weight: .semibold, design: .serif))
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
                    .font(.ff(size: 11))
                    .foregroundStyle(Color.ffInk3)
                Text("QUICK")
                    .font(.ff(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.ffInk3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([2.0, 3.0, 4.0, 5.0, 6.0], id: \.self) { preset in
                        Button {
                            Haptics.light()
                            vm.volumePerBagText = String(format: "%.0f", preset)
                        } label: {
                            let isSelected = vm.volumePerBagText == String(format: "%.0f", preset)
                            Text("\(Int(preset)) \(vm.unit.rawValue)")
                                .font(.ff(size: 13, weight: .semibold))
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

    // MARK: - Freeze date (core)

    private var freezeDateSection: some View {
        themedSection(title: "FROZEN ON") {
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
                HStack {
                    rowLabel(icon: "hourglass", label: "Expires")
                    Spacer()
                    Text(DateFormatter.freeze.string(from: vm.useCustomExpiration ? vm.expirationDate : computedExpiration))
                        .font(.ff(size: 14, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - More details (collapsed by default)

    private var moreDetailsSection: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMore.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.ff(size: 13))
                        .foregroundStyle(Color.ffInk3)
                    Text("MORE DETAILS")
                        .font(.ff(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.ffInk2)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.ff(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ffInk3)
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                expirationSection
                locationSection
                detailsSection
            }
        }
    }

    // MARK: - Expiration override

    private var expirationSection: some View {
        themedSection(title: "EXPIRATION") {
            VStack(spacing: 0) {
                Toggle(isOn: $vm.useCustomExpiration) {
                    rowLabel(icon: "calendar.badge.clock", label: "Custom expiration")
                }
                .tint(Color.ffTerra)
                .padding(.vertical, 10)

                if vm.useCustomExpiration {
                    FFDivider()
                    row {
                        rowLabel(icon: "hourglass", label: "Expires")
                    } value: {
                        DatePicker("", selection: $vm.expirationDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.ffTerra)
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
                .font(.ff(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .font(.ff(size: 15))
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
                        .padding(9)
                        .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose from previous entries")
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
                        .font(.ff(size: 14))
                        .foregroundStyle(Color.ffInk3)
                        .frame(width: 20)
                    TextField("Label code", text: $vm.labelCode)
                        .focused($focusedField, equals: .label)
                        .font(.ff(size: 15))
                        .foregroundStyle(Color.ffInk)
                        .tint(Color.ffTerra)
                }
                .padding(.vertical, 12)

                FFDivider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.ff(size: 14))
                        .foregroundStyle(Color.ffInk3)
                        .frame(width: 20)
                        .padding(.top, 4)
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                        .font(.ff(size: 15))
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

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Brick")
            }
            .font(.ff(size: 15, weight: .semibold))
            .foregroundStyle(Color.milkDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.milkDanger.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.milkDanger.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
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
                .font(.ff(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)
            Text(label)
                .font(.ff(size: 15))
                .foregroundStyle(Color.ffInk)
        }
    }

    // MARK: - Logic

    private var computedExpiration: Date {
        StashService.expirationDate(from: vm.freezeDate, months: appSettings.defaultExpirationMonths)
    }

    private func deleteBag() {
        guard let bag = bag else { return }
        context.delete(bag)
        do {
            try context.save()
            Haptics.warning()
            // Defer dismiss so the haptic plays before the sheet tears down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dismiss()
            }
        } catch {
            print("AddEditBagView: delete failed:", error)
        }
    }

    private func save(addAnother: Bool = false) {
        guard vm.validate() else {
            Haptics.warning()
            return
        }
        // Capture totals before saving for the confirmation card.
        let totalOz = vm.computedTotalOz
        let bags = vm.milkBagCount
        if vm.save(bag: bag, context: context, settings: appSettings) {
            Haptics.success()
            Announce.post("\(isEditing ? "Saved" : "Added to stash"): \(UnitConversion.formatted(totalOz, in: vm.unit)), \(bags) milk bag\(bags == 1 ? "" : "s")")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                savedSummary = (totalOz, bags)
            }
            // Hold the card briefly (also lets the success haptic play on device)
            // before dismissing the sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if addAnother {
                    withAnimation(.easeOut(duration: 0.2)) { savedSummary = nil }
                    vm.resetForNextBrick()
                    focusedField = .volumePerBag
                } else {
                    dismiss()
                }
            }
        } else {
            Haptics.warning()
        }
    }

    /// Batch entry: saves this Brick and keeps the sheet open with the
    /// date/location/unit intact for the next one.
    private var saveAndAddAnotherButton: some View {
        Button {
            save(addAnother: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square")
                Text("Save & add another")
            }
            .font(.ff(size: 15, weight: .semibold))
            .foregroundStyle(Color.ffTerra)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: Radius.l))
        }
        .buttonStyle(.plain)
        .disabled(!vm.isValid)
        .opacity(vm.isValid ? 1 : 0.5)
        .padding(.top, 4)
    }

    private func savedOverlay(oz: Double, bags: Int) -> some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ff(size: 48))
                    .foregroundStyle(Color.ffSage)
                Text(isEditing ? "Saved" : "Added to stash")
                    .font(.ff(size: 15, weight: .medium))
                    .foregroundStyle(Color.ffInk2)
                Text(UnitConversion.formatted(oz, in: vm.unit))
                    .font(.ff(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ffInk)
                Text("\(bags) milk bag\(bags == 1 ? "" : "s")")
                    .font(.ff(size: 13))
                    .foregroundStyle(Color.ffInk3)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(Color.ffSurface, in: RoundedRectangle(cornerRadius: Radius.hero))
            .overlay(RoundedRectangle(cornerRadius: Radius.hero).stroke(Color.ffLine, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
        }
        .transition(.opacity)
    }
}

#Preview {
    AddEditBagView(bag: nil)
        .modelContainer(PreviewData.container())
}
