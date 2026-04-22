// InventoryView.swift

import SwiftUI
import SwiftData

struct InventoryView: View {
    @Query private var allBags: [MilkBag]
    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @Environment(\.modelContext) private var context

    @State private var vm = InventoryViewModel()
    @State private var showAddBag = false
    @State private var editingBag: MilkBag? = nil
    @State private var bagToDelete: MilkBag? = nil
    @State private var showDeleteConfirm = false
    @State private var bagToDiscard: MilkBag? = nil
    @State private var showDiscardConfirm = false
    @State private var showFilters = false

    private var filteredBags: [MilkBag] { vm.filtered(allBags) }

    var body: some View {
        NavigationStack {
            Group {
                if filteredBags.isEmpty {
                    emptyState
                } else {
                    bagList
                }
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Ziplocks…")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { filterButton }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddBag = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showAddBag) { AddEditBagView(bag: nil) }
            .sheet(item: $editingBag) { bag in AddEditBagView(bag: bag) }
            .sheet(isPresented: $showFilters) {
                FilterSortSheet(vm: vm, allBags: allBags)
                    .presentationDetents([.medium, .large])
            }
            .alert("Delete Ziplock?", isPresented: $showDeleteConfirm, presenting: bagToDelete) { bag in
                Button("Delete", role: .destructive) { delete(bag) }
                Button("Cancel", role: .cancel) {}
            } message: { bag in
                Text("This will permanently remove the Ziplock frozen on \(DateFormatter.freeze.string(from: bag.freezeDate)).")
            }
            .alert("Discard Ziplock?", isPresented: $showDiscardConfirm, presenting: bagToDiscard) { bag in
                Button("Discard", role: .destructive) {
                    bag.status = .discarded
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: { bag in
                Text("Mark the Ziplock frozen on \(DateFormatter.freeze.string(from: bag.freezeDate)) as discarded?")
            }
        }
    }

    // MARK: - Bag List

    private var bagList: some View {
        List {
            Section {
                HStack {
                    Text("Sort")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Sort", selection: $vm.sortOption) {
                        ForEach(InventoryViewModel.SortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.milkBlue)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Section {
                ForEach(filteredBags) { bag in
                    BagRow(bag: bag, allBags: allBags, preferredUnit: appSettings.preferredUnit)
                        .contentShape(Rectangle())
                        .onTapGesture { editingBag = bag }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                bagToDelete = bag
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button {
                                bagToDiscard = bag
                                showDiscardConfirm = true
                            } label: { Label("Discard", systemImage: "xmark.circle") }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            if bag.status != .inStash {
                                Button {
                                    bag.status = .inStash
                                    try? context.save()
                                } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                                .tint(Color.milkGreen)
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.milkBlue.opacity(0.3))
            Text(vm.searchText.isEmpty ? "No Ziplocks yet" : "No matching Ziplocks")
                .font(.title3.weight(.semibold))
            Text(vm.searchText.isEmpty ? "Tap + to add your first Ziplock" : "Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter Button

    private var filterButton: some View {
        let isActive = !vm.filterLocation.isEmpty || !vm.filterBin.isEmpty
            || vm.filterStatus != .inStash || vm.filterExpiringSoon || vm.filterExpired

        return Button { showFilters = true } label: {
            Label("Filters", systemImage: isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            .foregroundStyle(isActive ? Color.milkBlue : .primary)
        }
    }

    private func delete(_ bag: MilkBag) {
        context.delete(bag)
        try? context.save()
    }
}

// MARK: - BagRow

struct BagRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let preferredUnit: MilkUnit

    private var seq: String { StashService.sequenceLabel(for: bag, in: allBags) }

    var body: some View {
        HStack(spacing: 12) {
            statusDot

            VStack(alignment: .leading, spacing: 4) {
                // Primary: freeze date + sequence
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: bag.freezeDate))
                        .font(.subheadline.weight(.semibold))
                    if !seq.isEmpty {
                        Text(seq).font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Milk bag count + volume each
                HStack(spacing: 4) {
                    Image(systemName: "bag.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.milkBlue.opacity(0.7))
                    Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s") × \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if bag.partialVolumeOz > 0.01 {
                        Text("+ \(UnitConversion.formatted(bag.partialVolumeOz, in: preferredUnit)) partial")
                            .font(.caption)
                            .foregroundStyle(Color.milkWarn)
                    }
                }

                // Location secondary
                if !bag.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.milkBlue.opacity(0.7))
                        Text(bag.location + (bag.slotBin.isEmpty ? "" : " · \(bag.slotBin)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Tags
                HStack(spacing: 6) {
                    if bag.isExpired         { TagBadge("Expired", color: .milkDanger) }
                    else if bag.isExpiringSoon(within: 14) {
                        let days = Calendar.current.dateComponents([.day],
                            from: Calendar.current.startOfDay(for: Date()),
                            to: bag.expirationDate).day ?? 0
                        TagBadge("Exp \(days)d", color: .milkWarn)
                    }
                    if bag.status == .used      { TagBadge("Used", color: .secondary) }
                    if bag.status == .discarded { TagBadge("Discarded", color: .milkDanger) }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("Exp \(DateFormatter.expiry.string(from: bag.expirationDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(.vertical, 2)
    }

    private var statusDot: some View {
        let color: Color = {
            if bag.isExpired                    { return .milkDanger }
            if bag.isExpiringSoon(within: 14)   { return .milkWarn }
            if bag.status == .inStash           { return .milkGreen }
            return .secondary
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }
}

struct TagBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Filter/Sort Sheet

struct FilterSortSheet: View {
    @Bindable var vm: InventoryViewModel
    let allBags: [MilkBag]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $vm.filterStatus) {
                        Text("All").tag(Optional<BagStatus>.none)
                        ForEach(BagStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(Optional(s))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Location") {
                    let locs = vm.uniqueLocations(allBags)
                    if locs.isEmpty {
                        Text("No locations set").foregroundStyle(.secondary)
                    } else {
                        Picker("Location", selection: $vm.filterLocation) {
                            Text("All").tag("")
                            ForEach(locs, id: \.self) { loc in Text(loc).tag(loc) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section("Expiration") {
                    Toggle("Expiring Soon (30 days)", isOn: $vm.filterExpiringSoon)
                    Toggle("Expired", isOn: $vm.filterExpired)
                }

                Section {
                    Button("Clear Filters") {
                        vm.filterLocation = ""
                        vm.filterBin = ""
                        vm.filterStatus = .inStash
                        vm.filterExpiringSoon = false
                        vm.filterExpired = false
                    }
                    .foregroundStyle(Color.milkDanger)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    InventoryView()
        .modelContainer(PreviewData.container())
}
