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
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    amountInputCard
                    optionsCard

                    if !amountFocused {
                        actionButtons
                    }

                    if !vm.recommendation.isEmpty {
                        recommendationCard
                    } else if !vm.amountText.isEmpty && Double(vm.amountText) != nil {
                        noRecommendationCard
                    }
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xl)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ffBg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Use Milk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Plan") { amountFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: vm.amountText)    { vm.updateRecommendation(bags: stashBags) }
            .onChange(of: vm.unit)          { vm.updateRecommendation(bags: stashBags) }
            .onChange(of: vm.includeExpired){ vm.updateRecommendation(bags: stashBags) }
            .onChange(of: amountFocused)    { vm.isAmountFieldFocused = amountFocused }
            .onAppear {
                vm.unit = appSettings.preferredUnit
                vm.includeExpired = appSettings.includeExpiredInFIFO
            }
            .alert("Confirm Use", isPresented: $vm.showConfirmAlert) {
                Button("Confirm") {
                    vm.applyUse(context: context)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(vm.confirmSummary(allBags: allBags))
            }
        }
    }

    // MARK: - Amount Input

    private var amountInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much do you need?")
                .font(.headline)

            HStack(spacing: 12) {
                TextField("Amount", text: $vm.amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                Picker("Unit", selection: $vm.unit) {
                    ForEach(MilkUnit.allCases, id: \.self) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }

            if vm.neededOz > 0 {
                let totalOz = stashBags.map(\.totalVolumeOz).reduce(0, +)
                let totalMilkBags = stashBags.map(\.milkBagCount).reduce(0, +)
                HStack {
                    Text("Available: \(UnitConversion.formatted(totalOz, in: vm.unit))")
                    Text("·")
                    Text("\(totalMilkBags) milk bags")
                }
                .font(.caption)
                .foregroundStyle(Color.ffInk2)
            }
        }
        .padding(Space.l)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ffLine, lineWidth: 0.5))
    }

    // MARK: - Options

    private var optionsCard: some View {
        Toggle(isOn: $vm.includeExpired) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.milkWarn)
                Text("Include Expired Bags")
                    .font(.subheadline)
            }
        }
        .padding(Space.l)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ffLine, lineWidth: 0.5))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                amountFocused = false
                vm.updateRecommendation(bags: stashBags)
            } label: {
                Label("Plan", systemImage: "list.clipboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.milkBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.l))
                    .foregroundStyle(Color.milkBlue)
            }
            .buttonStyle(.plain)

            if !vm.recommendation.isEmpty && vm.canFulfill {
                Button { vm.showConfirmAlert = true } label: {
                    Label("Confirm", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(vm.canFulfill ? Color.milkGreen : Color.milkWarn,
                                    in: RoundedRectangle(cornerRadius: Radius.l))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: vm.recommendation.isEmpty)
    }

    // MARK: - Recommendation Card

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FIFO Plan")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(UnitConversion.formatted(vm.totalCoveredOz, in: vm.unit))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(vm.canFulfill ? Color.milkGreen : Color.milkWarn)
                    let totalBags = vm.recommendation.map(\.wholeMilkBags).reduce(0, +)
                    Text("\(totalBags) milk bag\(totalBags == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.ffInk2)
                }
            }

            if !vm.canFulfill {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.milkWarn)
                    Text("Not enough milk in stash to fill this amount.")
                        .font(.caption)
                        .foregroundStyle(Color.milkWarn)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(vm.recommendation.enumerated()), id: \.element.id) { idx, item in
                    FIFOItemRow(item: item, stepNumber: idx + 1, allBags: allBags, displayUnit: vm.unit)
                    if idx < vm.recommendation.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color.cardBg, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ffLine, lineWidth: 0.5))
        }
    }

    private var noRecommendationCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.milkWarn.opacity(0.7))
            Text("No eligible Ziplocks found")
                .font(.subheadline)
                .foregroundStyle(Color.ffInk2)
            if !vm.includeExpired {
                Text("Try enabling 'Include Expired Bags'")
                    .font(.caption)
                    .foregroundStyle(Color.ffInk3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: Radius.l))
    }
}

// MARK: - FIFOItemRow

struct FIFOItemRow: View {
    let item: FIFOItem
    let stepNumber: Int
    let allBags: [MilkBag]
    let displayUnit: MilkUnit

    private var seq: String { StashService.sequenceLabel(for: item.bag, in: allBags) }

    var body: some View {
        HStack(spacing: Space.m) {
            // Step circle
            ZStack {
                Circle()
                    .fill(Color.milkBlue.opacity(0.12))
                    .frame(width: IconTile.size, height: IconTile.size)
                Text("\(stepNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.milkBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Ziplock identity
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: item.bag.freezeDate))
                        .font(.subheadline.weight(.semibold))
                    if !seq.isEmpty {
                        Text(seq).font(.caption).foregroundStyle(Color.ffInk2)
                    }
                    if item.bag.isExpired { TagBadge("Expired", color: .milkDanger) }
                }

                // Location
                if !item.bag.location.isEmpty {
                    Text(item.bag.location + (item.bag.slotBin.isEmpty ? "" : " · \(item.bag.slotBin)"))
                        .font(.caption)
                        .foregroundStyle(Color.ffInk2)
                }

                // What to take
                Label(
                    "\(item.wholeMilkBags) milk bag\(item.wholeMilkBags == 1 ? "" : "s")",
                    systemImage: "bag.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.milkBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.milkBlue.opacity(0.1), in: Capsule())
            }

            Spacer()

            // Total oz for this Ziplock
            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitConversion.formatted(item.takeOz, in: displayUnit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isWholeZiplock ? Color.milkDanger : Color.milkBlue)
                Text(item.isWholeZiplock ? "All bags" : "Some bags")
                    .font(.caption2)
                    .foregroundStyle(Color.ffInk2)
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
