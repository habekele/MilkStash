// UseMilkView.swift

import SwiftUI
import SwiftData

struct UseMilkView: View {
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]

    @Query private var allBags: [MilkBag]
    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm = UseMilkViewModel()
    @FocusState private var bagFieldFocused: Bool

    // Brief success confirmation shown after a use is logged, before dismiss.
    @State private var loggedSummary: (oz: Double, bags: Int)? = nil

    private let bagPresets: [Int] = [1, 2, 3, 4, 6, 8]

    private var sortedStashBags: [MilkBag] {
        stashBags
            .filter { vm.includeExpired || !$0.isExpired }
            .filter { $0.milkBagCount > 0 }
            .sorted {
                if $0.freezeDate != $1.freezeDate { return $0.freezeDate < $1.freezeDate }
                return $0.expirationDate < $1.expirationDate
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerArea
                    modeSection
                    if vm.mode == .auto {
                        bagInputSection
                    } else {
                        manualPickerSection
                    }
                    optionsSection

                    if !vm.recommendation.isEmpty {
                        planSection
                    } else if vm.mode == .auto && vm.bagsNeeded > 0 {
                        emptyPlanSection
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
                if let summary = loggedSummary {
                    successOverlay(oz: summary.oz, bags: summary.bags)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { bagFieldFocused = false }
                        .foregroundStyle(Color.ffTerra)
                }
            }
            .onChange(of: vm.bagCountText)   { vm.updateRecommendation(bags: stashBags) }
            .onChange(of: vm.mode)           { vm.updateRecommendation(bags: stashBags) }
            .onChange(of: vm.includeExpired) { vm.updateRecommendation(bags: stashBags) }
            .onChange(of: bagFieldFocused)   { vm.isBagFieldFocused = bagFieldFocused }
            .onAppear {
                Haptics.prepare()
                vm.unit = appSettings.preferredUnit
                vm.includeExpired = appSettings.includeExpiredInFIFO
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
                if !vm.recommendation.isEmpty && vm.canFulfill {
                    Button {
                        confirmUse()
                    } label: {
                        Text("Confirm")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.ffTerra, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Use Milk")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Confirm + success

    private func confirmUse() {
        // Capture totals before applyUse clears the recommendation.
        let oz = vm.totalCoveredOz
        let bags = vm.totalSelectedBags
        vm.applyUse(context: context)
        Haptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            loggedSummary = (oz, bags)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            dismiss()
        }
    }

    private func successOverlay(oz: Double, bags: Int) -> some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.ffSage)
                Text("Logged")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ffInk2)
                Text(UnitConversion.formatted(oz, in: vm.unit))
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ffInk)
                Text("\(bags) milk bag\(bags == 1 ? "" : "s")")
                    .font(.system(size: 13))
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

    // MARK: - Mode toggle

    private var modeSection: some View {
        Picker("Mode", selection: $vm.mode) {
            ForEach(UseMilkViewModel.SelectionMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.ffTerra)
    }

    // MARK: - Auto: bag count input

    private var bagInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "HOW MANY BAGS?")
            FFCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("0", text: $vm.bagCountText)
                            .keyboardType(.numberPad)
                            .focused($bagFieldFocused)
                            .font(.system(size: 44, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ffInk)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(vm.bagsNeeded == 1 ? "milk bag" : "milk bags")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                    }

                    quickBagPresetsRow

                    FFDivider()

                    let totalOz = stashBags.map(\.totalVolumeOz).reduce(0, +)
                    let totalMilkBags = stashBags.map(\.milkBagCount).reduce(0, +)
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ffInk3)
                        Text("Available: \(totalMilkBags) bag\(totalMilkBags == 1 ? "" : "s")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.ffInk2)
                        Text("·").foregroundStyle(Color.ffInk3)
                        Text(UnitConversion.formatted(totalOz, in: vm.unit))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.ffInk2)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var quickBagPresetsRow: some View {
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
                    ForEach(bagPresets, id: \.self) { preset in
                        Button {
                            vm.bagCountText = "\(preset)"
                        } label: {
                            let isSelected = vm.bagCountText == "\(preset)"
                            Text("\(preset)")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(minWidth: 28)
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
    }

    // MARK: - Manual: ziplock picker

    private var manualPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                FFEyebrow(text: "PICK ZIPLOCKS")
                Spacer()
                if !vm.manualSelections.isEmpty {
                    Button {
                        vm.resetManualSelections(in: stashBags)
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.ffTerra)
                    }
                    .buttonStyle(.plain)
                }
            }

            if sortedStashBags.isEmpty {
                FFCard(padding: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.ffInk4)
                        Text("No Ziplocks available")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.ffInk2)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                FFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedStashBags.enumerated()), id: \.element.id) { idx, bag in
                            ManualBagPickerRow(
                                bag: bag,
                                allBags: allBags,
                                displayUnit: vm.unit,
                                selected: vm.manualCount(for: bag.id),
                                onChange: { count in
                                    vm.setManualBagCount(for: bag.id, to: count, in: stashBags)
                                }
                            )
                            if idx < sortedStashBags.count - 1 {
                                FFDivider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "OPTIONS")
            FFCard(padding: 12) {
                Toggle(isOn: $vm.includeExpired) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ffInk3)
                            .frame(width: 20)
                        Text("Include expired bags")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.ffInk)
                    }
                }
                .tint(Color.ffTerra)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.canFulfill ? Color.ffSage : Color.ffButter)
                    .frame(width: 7, height: 7)
                FFEyebrow(text: vm.mode == .auto ? "FIFO PLAN" : "YOUR SELECTION")
            }

            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bags")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color.ffInk3)
                            Text("\(vm.totalSelectedBags)")
                                .font(.system(size: 22, weight: .regular, design: .serif))
                                .foregroundStyle(Color.ffInk)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color.ffInk3)
                            Text(UnitConversion.formatted(vm.totalCoveredOz, in: vm.unit))
                                .font(.system(size: 22, weight: .regular, design: .serif))
                                .foregroundStyle(Color.ffInk)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if vm.mode == .auto && !vm.canFulfill {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("Not enough bags in stash to cover this amount.")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color.ffButter)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ffButterSoft)
                    }

                    FFDivider()

                    ForEach(Array(vm.recommendation.enumerated()), id: \.element.id) { idx, item in
                        FIFOItemRow(item: item, stepNumber: idx + 1, allBags: allBags, displayUnit: vm.unit)
                        if idx < vm.recommendation.count - 1 {
                            FFDivider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private var emptyPlanSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "FIFO PLAN")
            FFCard(padding: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.ffInk4)
                    Text("No eligible Ziplocks found")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ffInk2)
                    if !vm.includeExpired {
                        Text("Try turning on Include expired bags")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ffInk3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Manual picker row

struct ManualBagPickerRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let displayUnit: MilkUnit
    let selected: Int
    let onChange: (Int) -> Void

    private var seq: String { StashService.sequenceLabel(for: bag, in: allBags) }
    private var isPicked: Bool { selected > 0 }

    var body: some View {
        HStack(spacing: Space.m) {
            // Calendar block
            let calColor = bag.isExpiringSoon(within: 14) ? Color.ffButter : Color.ffTerra
            VStack(spacing: 0) {
                Text(DateFormatter.calMonth.string(from: bag.freezeDate).uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(calColor)
                Text(DateFormatter.calDay.string(from: bag.freezeDate))
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(calColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(calColor.opacity(0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: bag.freezeDate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ffInk)
                    if !seq.isEmpty {
                        Text(seq)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ffInk3)
                    }
                }
                Text("\(bag.milkBagCount) × \(UnitConversion.formatted(bag.volumePerBagOz, in: displayUnit)) available")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ffInk2)
                if bag.isExpired {
                    TagBadge("Expired", color: .milkDanger)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Button {
                    onChange(max(0, selected - 1))
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(selected > 0 ? Color.ffTerra : Color.ffInk4)
                }
                .buttonStyle(.plain)
                .disabled(selected == 0)

                Text("\(selected)")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(isPicked ? Color.ffTerra : Color.ffInk3)
                    .frame(minWidth: 22)

                Button {
                    onChange(min(bag.milkBagCount, selected + 1))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(selected < bag.milkBagCount ? Color.ffTerra : Color.ffInk4)
                }
                .buttonStyle(.plain)
                .disabled(selected >= bag.milkBagCount)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(isPicked ? Color.ffTerraSoft.opacity(0.45) : Color.clear)
    }
}

// MARK: - Plan row

struct FIFOItemRow: View {
    let item: FIFOItem
    let stepNumber: Int
    let allBags: [MilkBag]
    let displayUnit: MilkUnit

    private var seq: String { StashService.sequenceLabel(for: item.bag, in: allBags) }

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                Circle()
                    .fill(Color.ffTerraSoft)
                    .frame(width: IconTile.size, height: IconTile.size)
                Text("\(stepNumber)")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Color.ffTerra)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: item.bag.freezeDate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ffInk)
                    if !seq.isEmpty {
                        Text(seq)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ffInk3)
                    }
                    if item.bag.isExpired { TagBadge("Expired", color: .milkDanger) }
                }

                if !item.bag.location.isEmpty {
                    Text(item.bag.location + (item.bag.slotBin.isEmpty ? "" : " · \(item.bag.slotBin)"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ffInk2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 9))
                    Text("\(item.wholeMilkBags) milk bag\(item.wholeMilkBags == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.ffTerra)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.ffTerraSoft, in: Capsule())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitConversion.formatted(item.takeOz, in: displayUnit))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(item.isWholeZiplock ? Color.milkDanger : Color.ffInk)
                    .monospacedDigit()
                Text(item.isWholeZiplock ? "All bags" : "Some bags")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

#Preview {
    UseMilkView()
        .modelContainer(PreviewData.container())
}
