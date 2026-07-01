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
    @State private var bagToUse: MilkBag? = nil
    @State private var showFilters = false
    @State private var showOther = false

    private var filteredBags: [MilkBag] { vm.filtered(allBags) }
    private var stashBags: [MilkBag] { allBags.filter { $0.status == .inStash } }

    // Summary counts
    private var totalStashOz: Double { stashBags.map(\.totalVolumeOz).reduce(0, +) }
    private var ziplockCount: Int    { stashBags.count }
    private var bagCount: Int        { stashBags.map(\.milkBagCount).reduce(0, +) }

    // Days until the soonest-expiring brick in stash (nil if stash empty)
    private var soonestExpiryDays: Int? {
        guard let soonest = stashBags.map(\.expirationDate).min() else { return nil }
        return Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: soonest).day
    }

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
            .sheet(item: $bagToUse) { bag in UseMilkView(preselectedBagID: bag.id) }
            .sheet(isPresented: $showFilters) {
                FilterSortSheet(vm: vm, allBags: allBags)
                    .presentationDetents([.medium, .large])
            }
            .alert("Delete Brick?", isPresented: $showDeleteConfirm, presenting: bagToDelete) { bag in
                Button("Delete", role: .destructive) { delete(bag) }
                Button("Cancel", role: .cancel) {}
            } message: { bag in
                Text("This will permanently remove the Brick frozen on \(DateFormatter.freeze.string(from: bag.freezeDate)).")
            }
            .alert("Discard Brick?", isPresented: $showDiscardConfirm, presenting: bagToDiscard) { bag in
                Button("Discard", role: .destructive) {
                    do {
                        try StashService.discard(bag: bag, unit: appSettings.preferredUnit, context: context)
                        Haptics.warning()
                    } catch { print("InventoryView: discard failed:", error) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { bag in
                Text("Mark the Brick frozen on \(DateFormatter.freeze.string(from: bag.freezeDate)) as discarded?")
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
                        .font(.ff(size: 20))
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
                            .font(.ff(size: 18))
                            .foregroundStyle(showSearch ? Color.ffTerra : Color.ffInk3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")

                    Button { showAddBag = true } label: {
                        Image(systemName: "plus")
                            .font(.ff(size: 20, weight: .semibold))
                            .foregroundStyle(Color.ffTerra)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Brick")
                }
            }

            Text("The Stash")
                .font(.ff(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)

            summaryStrip
                .padding(.top, 4)
        }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        let unit = appSettings.preferredUnit
        return HStack(spacing: 8) {
            summaryTile(
                value: UnitConversion.formatted(totalStashOz, in: unit),
                caption: "IN STASH",
                bg: Color.ffSurface, border: Color.ffLine,
                fg: Color.ffInk, capFg: Color.ffInk3
            )
            summaryTile(
                value: "\(ziplockCount) brick\(ziplockCount == 1 ? "" : "s")",
                caption: "\(bagCount) BAGS",
                bg: Color.ffSurface, border: Color.ffLine,
                fg: Color.ffInk, capFg: Color.ffInk3
            )
            useNextTile
        }
    }

    @ViewBuilder
    private var useNextTile: some View {
        if let d = soonestExpiryDays {
            if d < 0 {
                summaryTile(value: "Overdue", caption: "USE NOW",
                            bg: Color.milkDanger.opacity(0.10),
                            border: Color.milkDanger.opacity(0.25),
                            fg: Color.milkDanger, capFg: Color.milkDanger)
            } else {
                let urgent = d <= 14
                // Ink text on the butter tint (butter-on-butter fails contrast);
                // urgency reads from the tinted background and border.
                Button {
                    vm.filterStatus = nil
                    vm.filterExpiringSoon = true
                } label: {
                    summaryTile(value: d == 0 ? "Today" : "\(d) day\(d == 1 ? "" : "s")",
                                caption: "USE NEXT",
                                bg: urgent ? Color.ffButterSoft : Color.ffSurface,
                                border: urgent ? Color.ffButter.opacity(0.3) : Color.ffLine,
                                fg: Color.ffInk,
                                capFg: urgent ? Color.ffInk2 : Color.ffInk3)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Filters to Bricks expiring soon")
            }
        } else {
            summaryTile(value: "—", caption: "USE NEXT",
                        bg: Color.ffSurface, border: Color.ffLine,
                        fg: Color.ffInk3, capFg: Color.ffInk3)
        }
    }

    private func summaryTile(value: String, caption: String,
                             bg: Color, border: Color,
                             fg: Color, capFg: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.ff(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.ff(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(capFg)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(border, lineWidth: 0.5))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.ff(size: 15))
                .foregroundStyle(Color.ffInk3)
            TextField("Search by date, bin, or note…", text: $vm.searchText)
                .font(.ff(size: 15))
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
                .font(.ff(size: 13))
                .foregroundStyle(Color.ffInk3)

            Menu {
                ForEach(InventoryViewModel.SortOption.allCases, id: \.self) { opt in
                    Button(opt.rawValue) { vm.sortOption = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sorted by \(vm.sortOption.rawValue)")
                        .font(.ff(size: 13))
                        .foregroundStyle(Color.ffInk2)
                    Image(systemName: "chevron.down")
                        .font(.ff(size: 10))
                        .foregroundStyle(Color.ffInk3)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(filteredBags.count) shown")
                .font(.ff(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ffInk3)
        }
    }

    // MARK: - Grouped Content

    private var groupedContent: some View {
        VStack(spacing: 16) {
            if !useSoonBags.isEmpty {
                inventoryGroup(
                    title: "USE SOON",
                    accent: Color.ffButter,
                    bags: useSoonBags
                )
            }
            if !plentyBags.isEmpty {
                inventoryGroup(
                    title: "PLENTY OF TIME",
                    accent: Color.ffSage,
                    bags: plentyBags
                )
            }
            if !otherBags.isEmpty {
                inventoryGroup(
                    title: "OTHER",
                    accent: Color.ffInk3,
                    bags: otherBags,
                    collapsible: true
                )
            }
        }
    }

    private func inventoryGroup(title: String, accent: Color, bags: [MilkBag],
                                collapsible: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if collapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showOther.toggle() }
                } label: {
                    groupHeader(title: title, accent: accent, count: bags.count,
                                chevron: showOther ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)

                if showOther {
                    groupCard(accent: accent, bags: bags)
                }
            } else {
                groupHeader(title: title, accent: accent, count: bags.count, chevron: nil)
                groupCard(accent: accent, bags: bags)
            }
        }
    }

    private func groupHeader(title: String, accent: Color, count: Int, chevron: String?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            FFEyebrow(text: "\(title) · \(count)")
            Spacer()
            if let chevron {
                Image(systemName: chevron)
                    .font(.ff(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ffInk3)
            }
        }
        .contentShape(Rectangle())
    }

    private func groupCard(accent: Color, bags: [MilkBag]) -> some View {
        HStack(spacing: 0) {
            // Urgency color rail
            Rectangle()
                .fill(accent)
                .frame(width: 3)

            VStack(spacing: 0) {
                ForEach(Array(bags.enumerated()), id: \.element.id) { idx, bag in
                    FFInventoryRow(
                        bag: bag,
                        allBags: allBags,
                        preferredUnit: appSettings.preferredUnit,
                        onEdit: { editingBag = bag },
                        onUse: bag.status == .inStash && bag.milkBagCount > 0
                            ? { bagToUse = bag } : nil,
                        onDiscard: bag.status == .inStash
                            ? { bagToDiscard = bag; showDiscardConfirm = true } : nil,
                        onRestore: bag.status != .inStash
                            ? { restore(bag) } : nil,
                        onDelete: { bagToDelete = bag; showDeleteConfirm = true }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingBag = bag }
                    .contextMenu {
                        Button {
                            editingBag = bag
                        } label: { Label("Edit", systemImage: "pencil") }

                        if bag.status == .inStash {
                            if bag.milkBagCount > 0 {
                                Button {
                                    bagToUse = bag
                                } label: { Label("Use from this Brick", systemImage: "drop") }
                            }
                            Button {
                                bagToDiscard = bag
                                showDiscardConfirm = true
                            } label: { Label("Discard", systemImage: "xmark.circle") }
                        } else {
                            Button {
                                restore(bag)
                            } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                        }

                        Button(role: .destructive) {
                            bagToDelete = bag
                            showDeleteConfirm = true
                        } label: { Label("Delete", systemImage: "trash") }
                    }

                    if idx < bags.count - 1 {
                        FFDivider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color.ffSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ffLine, lineWidth: 0.5))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.ff(size: 56))
                .foregroundStyle(Color.ffTerra.opacity(0.5))
            Text(vm.searchText.isEmpty ? "No Bricks yet" : "No matching Bricks")
                .font(.ff(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
            Text(vm.searchText.isEmpty
                 ? "Tap + to add your first Brick"
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

    private func restore(_ bag: MilkBag) {
        bag.status = .inStash
        do { try context.save() } catch { print("InventoryView: save failed:", error) }
    }
}

// MARK: - InventoryViewModel extension for hasActiveFilters

extension InventoryViewModel {
    var hasActiveFilters: Bool {
        // nil status ("All") widens the view rather than filtering it, so it
        // shouldn't light up the filter icon.
        !filterLocation.isEmpty || !filterBin.isEmpty
            || (filterStatus != nil && filterStatus != .inStash)
            || filterExpiringSoon || filterExpired
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
                .font(.ff(size: 13, weight: .medium))
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

    // When provided, the trailing chevron becomes an ellipsis menu so row
    // actions are discoverable without knowing about long-press.
    var onEdit: (() -> Void)? = nil
    var onUse: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

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
                    .font(.ff(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(calColor)
                Text(DateFormatter.calDay.string(from: bag.freezeDate))
                    .font(.ff(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(calColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(calColor.opacity(0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 5) {
                // Brick label
                HStack(spacing: 6) {
                    Text(DateFormatter.freeze.string(from: bag.freezeDate))
                        .font(.ff(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ffInk)
                    if !seq.isEmpty {
                        Text(seq)
                            .font(.ff(size: 11, weight: .medium))
                            .foregroundStyle(Color.ffInk3)
                    }
                }

                // Tags (only when relevant)
                HStack(spacing: 5) {
                    if bag.isExpired         { TagBadge("Expired", color: .milkDanger) }
                    else if bag.isExpiringSoon(within: 14) {
                        TagBadge("Use in \(max(daysLeft, 0))d", color: Color.ffButter)
                    }
                    if bag.status == .used      { TagBadge("Used", color: Color.ffInk3) }
                    if bag.status == .discarded { TagBadge("Discarded", color: .milkDanger) }
                }
            }

            Spacer(minLength: 6)

            // Single clean volume summary
            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.ff(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                    .monospacedDigit()
                Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s")")
                    .font(.ff(size: 11, weight: .medium))
                    .foregroundStyle(Color.ffInk3)
            }

            if onEdit != nil {
                Menu {
                    if let onEdit {
                        Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    }
                    if let onUse {
                        Button { onUse() } label: { Label("Use from this Brick", systemImage: "drop") }
                    }
                    if let onDiscard {
                        Button { onDiscard() } label: { Label("Discard", systemImage: "xmark.circle") }
                    }
                    if let onRestore {
                        Button { onRestore() } label: { Label("Restore", systemImage: "arrow.uturn.left") }
                    }
                    if let onDelete {
                        Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.ff(size: 17))
                        .foregroundStyle(Color.ffInk3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Brick actions")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ffInk3)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
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
                        .font(.ff(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.ffTerra, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Text("Filter & Sort")
                .font(.ff(size: 32, weight: .regular, design: .serif))
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
                            .font(.ff(size: 14))
                            .foregroundStyle(Color.ffInk3)
                            .frame(width: 20)
                        Text("No locations set")
                            .font(.ff(size: 14))
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
                    .font(.ff(size: 13, weight: .semibold))
                Text("Clear filters")
                    .font(.ff(size: 14, weight: .semibold))
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
                    .font(.ff(size: 14))
                    .foregroundStyle(isSelected ? Color.ffTerra : Color.ffInk3)
                    .frame(width: 20)
                Text(label)
                    .font(.ff(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.ffInk)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.ff(size: 13, weight: .semibold))
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
                .font(.ff(size: 14))
                .foregroundStyle(Color.ffInk3)
                .frame(width: 20)
            Text(label)
                .font(.ff(size: 15))
                .foregroundStyle(Color.ffInk)
        }
    }
}

#Preview {
    InventoryView()
        .modelContainer(PreviewData.container())
}
