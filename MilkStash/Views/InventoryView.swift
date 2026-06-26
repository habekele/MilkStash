// InventoryView.swift

import SwiftUI
import SwiftData

struct InventoryView: View {
    @Query private var allBags: [MilkBag]
    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @Environment(\.modelContext) private var context

    @State private var vm = InventoryViewModel()
    @State private var showSearch = false
    @State private var showAddBag = false
    @State private var editingBag: MilkBag? = nil
    @State private var bagToDelete: MilkBag? = nil
    @State private var showDeleteConfirm = false
    @State private var bagToDiscard: MilkBag? = nil
    @State private var showDiscardConfirm = false
    @State private var showFilters = false

    private var filteredBags: [MilkBag] { vm.filtered(allBags) }
    private var stashBags: [MilkBag] { allBags.filter { $0.status == .inStash } }

    // Summary counts
    private var totalStashOz: Double { stashBags.map(\.totalVolumeOz).reduce(0, +) }
    private var ziplockCount: Int    { stashBags.count }
    private var bagCount: Int        { stashBags.map(\.milkBagCount).reduce(0, +) }

    // Days threshold for "Use Soon" group — matches the expiring-soon filter chip
    private let useSoonDays = 30

    // Grouped lists
    private var useSoonBags: [MilkBag] {
        filteredBags.filter { $0.status == .inStash && $0.isExpiringSoon(within: useSoonDays) }
    }
    private var plentyBags: [MilkBag] {
        filteredBags.filter { $0.status == .inStash && !$0.isExpiringSoon(within: useSoonDays) }
    }
    private var otherBags: [MilkBag] {
        filteredBags.filter { $0.status != .inStash }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    headerSection
                    if showSearch { searchBar }
                    filterChipsRow
                    sortRow

                    if filteredBags.isEmpty {
                        emptyState
                    } else {
                        groupedContent
                    }
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.tabBarClearance)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .tracksTabBar()
            .navigationBarHidden(true)
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
                    do {
                        try StashService.discard(bag: bag, unit: appSettings.preferredUnit, context: context)
                        Haptics.warning()
                    } catch { print("InventoryView: discard failed:", error) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { bag in
                Text("Mark the Ziplock frozen on \(DateFormatter.freeze.string(from: bag.freezeDate)) as discarded?")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { showFilters = true } label: {
                    Image(systemName: vm.hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(vm.hasActiveFilters ? Color.ffTerra : Color.ffInk3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter")

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        showSearch.toggle()
                        if !showSearch { vm.searchText = "" }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundStyle(showSearch ? Color.ffTerra : Color.ffInk3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")

                    Button { showAddBag = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.ffTerra)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Ziplock")
                }
            }

            Text("The Stash")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)

            // Eyebrow with counts
            let unit = appSettings.preferredUnit
            FFEyebrow(text: "\(ziplockCount) ZIPLOCKS · \(bagCount) BAGS · \(UnitConversion.formatted(totalStashOz, in: unit))")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.ffInk3)
            TextField("Search by date, bin, or note…", text: $vm.searchText)
                .font(.system(size: 15))
                .foregroundStyle(Color.ffInk)
                .tint(Color.ffTerra)
            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ffInk3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + 2)
        .background(Color.ffSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.ffLine, lineWidth: 0.5))
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FFFilterChip(label: "All", isActive: vm.filterStatus == nil && !vm.filterExpiringSoon) {
                    vm.filterLocation = ""
                    vm.filterBin = ""
                    vm.filterStatus = nil
                    vm.filterExpiringSoon = false
                    vm.filterExpired = false
                }
                FFFilterChip(label: "Use soon", isActive: vm.filterExpiringSoon) {
                    vm.filterExpiringSoon.toggle()
                    if vm.filterExpiringSoon { vm.filterStatus = nil }
                }
                // Location chips from unique locations
                let locs = vm.uniqueLocations(allBags)
                ForEach(locs, id: \.self) { loc in
                    FFFilterChip(label: loc, isActive: vm.filterLocation == loc) {
                        vm.filterLocation = vm.filterLocation == loc ? "" : loc
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Sort Row

    private var sortRow: some View {
        HStack {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(Color.ffInk3)

            Menu {
                ForEach(InventoryViewModel.SortOption.allCases, id: \.self) { opt in
                    Button(opt.rawValue) { vm.sortOption = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sorted by \(vm.sortOption.rawValue)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ffInk2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ffInk3)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(filteredBags.count) items")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ffInk3)
        }
    }

    // MARK: - Grouped Content

    private var groupedContent: some View {
        VStack(spacing: 16) {
            if !useSoonBags.isEmpty {
                inventoryGroup(
                    title: "USE SOON",
                    dotColor: Color.ffTerra,
                    bags: useSoonBags
                )
            }
            if !plentyBags.isEmpty {
                inventoryGroup(
                    title: "PLENTY OF TIME",
                    dotColor: Color.ffSage,
                    bags: plentyBags
                )
            }
            if !otherBags.isEmpty {
                inventoryGroup(
                    title: "OTHER",
                    dotColor: Color.ffInk3,
                    bags: otherBags
                )
            }
        }
    }

    private func inventoryGroup(title: String, dotColor: Color, bags: [MilkBag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                FFEyebrow(text: title)
            }

            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(bags.enumerated()), id: \.element.id) { idx, bag in
                        FFInventoryRow(
                            bag: bag,
                            allBags: allBags,
                            preferredUnit: appSettings.preferredUnit
                        )
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
                            .tint(Color.ffButter)
                        }
                        .swipeActions(edge: .leading) {
                            if bag.status != .inStash {
                                Button {
                                    bag.status = .inStash
                                    do { try context.save() } catch { print("InventoryView: save failed:", error) }
                                } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                                .tint(Color.ffSage)
                            }
                        }

                        if idx < bags.count - 1 {
                            FFDivider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.ffTerra.opacity(0.5))
            Text(vm.searchText.isEmpty ? "No Ziplocks yet" : "No matching Ziplocks")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
            Text(vm.searchText.isEmpty
                 ? "Tap + to add your first Ziplock"
                 : "Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundStyle(Color.ffInk2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func delete(_ bag: MilkBag) {
        context.delete(bag)
        do { try context.save(); Haptics.warning() } catch { print("InventoryView: save failed:", error) }
    }
}

// MARK: - InventoryViewModel extension for hasActiveFilters

extension InventoryViewModel {
    var hasActiveFilters: Bool {
        !filterLocation.isEmpty || !filterBin.isEmpty
            || filterStatus != .inStash || filterExpiringSoon || filterExpired
    }
}

// MARK: - Filter Chip

struct FFFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.ffSurface : Color.ffInk2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? Color.ffInk : Color.ffSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.ffLine, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inventory Row

struct FFInventoryRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let preferredUnit: MilkUnit

    private var seq: String { StashService.sequenceLabel(for: bag, in: allBags) }

    private var daysLeft: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: bag.expirationDate).day ?? 0
    }

    private var statusColor: Color {
        if bag.isExpired                  { return Color.milkDanger }
        if bag.isExpiringSoon(within: 14) { return Color.ffButter }
        if bag.status == .inStash         { return Color.ffSage }
        return Color.ffInk3
    }

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
                // Ziplock label
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: bag.freezeDate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ffInk)
                    if !seq.isEmpty {
                        Text(seq)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.ffInk3)
                    }
                }

                // Bag count × volume
                HStack(spacing: 4) {
                    Text("\(bag.milkBagCount) × \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ffInk2)
                }

                // Mini bag dots
                if bag.milkBagCount > 0 {
                    miniBagDots
                }

                // Tags
                HStack(spacing: 5) {
                    if bag.isExpired         { TagBadge("Expired", color: .milkDanger) }
                    else if bag.isExpiringSoon(within: 14) {
                        TagBadge("Exp \(max(daysLeft, 0))d", color: Color.ffButter)
                    }
                    if bag.status == .used      { TagBadge("Used", color: Color.ffInk3) }
                    if bag.status == .discarded { TagBadge("Discarded", color: .milkDanger) }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                    .monospacedDigit()
                Text("EXP \(DateFormatter.expiry.string(from: bag.expirationDate))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ffInk3)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }

    private var miniBagDots: some View {
        HStack(spacing: 3) {
            let count = min(bag.milkBagCount, 10)
            ForEach(0..<count, id: \.self) { _ in
                let dotColor: Color = bag.isExpired ? Color.milkDanger
                    : bag.isExpiringSoon(within: 14) ? Color.ffButter : Color.ffSage
                RoundedRectangle(cornerRadius: 2)
                    .fill(dotColor)
                    .frame(width: 8, height: 10)
            }
            if bag.milkBagCount > 10 {
                Text("+\(bag.milkBagCount - 10)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
            }
        }
    }
}

// Keep legacy BagRow for any references
struct BagRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let preferredUnit: MilkUnit

    var body: some View {
        FFInventoryRow(bag: bag, allBags: allBags, preferredUnit: preferredUnit)
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
            .background(color.opacity(0.22), in: Capsule())
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
            ScrollView {
                VStack(spacing: 14) {
                    headerArea
                    sortSection
                    statusSection
                    locationSection
                    expirationSection
                    clearButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.ffTerra, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Text("Filter & Sort")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Sort

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "SORT BY")
            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(InventoryViewModel.SortOption.allCases.enumerated()), id: \.element) { idx, option in
                        selectableRow(
                            icon: sortIcon(for: option),
                            label: option.rawValue,
                            isSelected: vm.sortOption == option
                        ) { vm.sortOption = option }
                        if idx < InventoryViewModel.SortOption.allCases.count - 1 {
                            FFDivider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func sortIcon(for option: InventoryViewModel.SortOption) -> String {
        switch option {
        case .freezeOldest: return "arrow.up"
        case .freezeNewest: return "arrow.down"
        case .expiration:   return "hourglass"
        case .volume:       return "drop.fill"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "STATUS")
            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    selectableRow(icon: "circle.dashed", label: "All", isSelected: vm.filterStatus == nil) {
                        vm.filterStatus = nil
                    }
                    FFDivider().padding(.leading, 50)
                    ForEach(Array(BagStatus.allCases.enumerated()), id: \.element) { idx, s in
                        selectableRow(
                            icon: statusIcon(for: s),
                            label: s.rawValue,
                            isSelected: vm.filterStatus == s
                        ) { vm.filterStatus = s }
                        if idx < BagStatus.allCases.count - 1 {
                            FFDivider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(for s: BagStatus) -> String {
        switch s {
        case .inStash:   return "shippingbox.fill"
        case .used:      return "checkmark.circle"
        case .discarded: return "xmark.circle"
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "LOCATION")
            FFCard(padding: 0) {
                let locs = vm.uniqueLocations(allBags)
                if locs.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ffInk3)
                            .frame(width: 20)
                        Text("No locations set")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ffInk2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        selectableRow(
                            icon: "circle.dashed",
                            label: "All locations",
                            isSelected: vm.filterLocation.isEmpty
                        ) { vm.filterLocation = "" }
                        FFDivider().padding(.leading, 50)
                        ForEach(Array(locs.enumerated()), id: \.element) { idx, loc in
                            selectableRow(
                                icon: "tray.full",
                                label: loc,
                                isSelected: vm.filterLocation == loc
                            ) { vm.filterLocation = loc }
                            if idx < locs.count - 1 {
                                FFDivider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expiration

    private var expirationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            FFEyebrow(text: "EXPIRATION")
            FFCard(padding: 12) {
                VStack(spacing: 0) {
                    Toggle(isOn: $vm.filterExpiringSoon) {
                        toggleLabel(icon: "clock.badge.exclamationmark", label: "Expiring soon (30 days)")
                    }
                    .tint(Color.ffTerra)
                    .padding(.vertical, 6)

                    FFDivider()

                    Toggle(isOn: $vm.filterExpired) {
                        toggleLabel(icon: "exclamationmark.triangle", label: "Expired")
                    }
                    .tint(Color.ffTerra)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Clear

    private var clearButton: some View {
        Button {
            vm.filterLocation = ""
            vm.filterBin = ""
            vm.filterStatus = .inStash
            vm.filterExpiringSoon = false
            vm.filterExpired = false
            vm.sortOption = .freezeOldest
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Clear filters")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.milkDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.milkDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.milkDanger.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func selectableRow(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.ffTerra : Color.ffInk3)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.ffInk)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ffTerra)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleLabel(icon: String, label: String) -> some View {
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
    InventoryView()
        .modelContainer(PreviewData.container())
}
