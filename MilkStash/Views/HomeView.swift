// HomeView.swift

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]

    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @State private var vm = HomeViewModel()
    @State private var showAddBag = false
    @State private var showUseMilk = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    stashSummaryCard
                    statsRow
                    quickActionsSection
                    expiringSoonSection
                    recentlyAddedSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FreezeFlow")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showAddBag)  { AddEditBagView(bag: nil) }
        .sheet(isPresented: $showUseMilk) { UseMilkView() }
    }

    // MARK: - Stash Summary Card

    private var stashSummaryCard: some View {
        let totalOz   = vm.totalOz(stashBags)
        let unit      = appSettings.preferredUnit
        let days      = vm.daysWorth(stashBags, dailyOz: appSettings.dailyOzGoal)
        let ziplocks  = vm.ziplockCount(stashBags)
        let milkBags  = vm.totalMilkBagCount(stashBags)

        return ZStack(alignment: .topTrailing) {
            // Background gradient
            LinearGradient(
                colors: [Color.milkIndigo, Color.milkIndigo.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 160)
                .offset(x: 60, y: -40)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 100)
                .offset(x: 20, y: 60)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Label("Your Stash", systemImage: "snowflake")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(0.5)
                    Spacer()
                    if totalOz < appSettings.lowStashThresholdOz && ziplocks > 0 {
                        Label("Low", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.milkWarn)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.milkWarn.opacity(0.2), in: Capsule())
                    }
                }

                // Big total
                VStack(alignment: .leading, spacing: 4) {
                    Text(UnitConversion.formatted(totalOz, in: unit))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(String(format: "%.1f days worth  ·  %@/day", days,
                         UnitConversion.formatted(appSettings.dailyOzGoal, in: unit)))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }

                // Count pills
                HStack(spacing: 10) {
                    StatPill(value: "\(ziplocks)", label: ziplocks == 1 ? "Ziplock" : "Ziplocks", icon: "bag.fill")
                    StatPill(value: "\(milkBags)", label: milkBags == 1 ? "Milk Bag" : "Milk Bags", icon: "drop.fill")
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Color.milkIndigo.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let unit     = appSettings.preferredUnit
        let totalOz  = vm.totalOz(stashBags)
        let expiring = StashService.expiringSoon(bags: stashBags, within: 7).count

        let oldest   = stashBags.filter { $0.status == .inStash }
                                .sorted { $0.freezeDate < $1.freezeDate }
                                .first

        return HStack(spacing: 12) {
            MiniStatCard(
                icon: "calendar.badge.clock",
                iconColor: Color.milkCoral,
                title: "Oldest Bag",
                value: oldest.map { DateFormatter.shortDate.string(from: $0.freezeDate) } ?? "—"
            )
            MiniStatCard(
                icon: "clock.badge.exclamationmark",
                iconColor: Color.milkWarn,
                title: "Exp. Soon",
                value: expiring == 0 ? "None" : "\(expiring) bag\(expiring == 1 ? "" : "s")"
            )
            MiniStatCard(
                icon: "chart.bar.fill",
                iconColor: Color.milkSage,
                title: "Avg / Ziplock",
                value: stashBags.isEmpty ? "—" : UnitConversion.formatted(
                    totalOz / Double(max(stashBags.count, 1)), in: unit
                )
            )
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Actions")

            HStack(spacing: 12) {
                QuickActionButton(title: "Add Ziplock", icon: "plus.circle.fill", color: Color.milkIndigo) {
                    showAddBag = true
                }
                QuickActionButton(title: "Use Milk", icon: "drop.fill", color: Color.milkCoral) {
                    showUseMilk = true
                }
            }
        }
    }

    // MARK: - Expiring Soon

    private var expiringSoonSection: some View {
        let expiring = vm.expiringSoon(stashBags)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Expiring Soon")
                Spacer()
                Picker("Within", selection: $vm.expiringSoonFilter) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            if expiring.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(Color.milkSage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All good!")
                            .font(.subheadline.weight(.semibold))
                        Text("No Ziplocks expiring within \(vm.expiringSoonFilter) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.milkSage.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(expiring.enumerated()), id: \.element.id) { idx, bag in
                        ExpiringBagRow(bag: bag, allBags: stashBags, preferredUnit: appSettings.preferredUnit)
                        if idx < expiring.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
            }
        }
    }

    // MARK: - Recently Added

    private var recentlyAddedSection: some View {
        let recent = stashBags
            .filter { $0.status == .inStash }
            .sorted { $0.freezeDate > $1.freezeDate }
            .prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently Added")

            if recent.isEmpty {
                Text("No bags in stash yet — tap Add Ziplock to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, bag in
                        RecentBagRow(bag: bag, preferredUnit: appSettings.preferredUnit)
                        if idx < recent.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
            }
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("\(value) \(label)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.15), in: Capsule())
    }
}

struct MiniStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

struct CountBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 52)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ExpiringBagRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let preferredUnit: MilkUnit

    private var daysLeft: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: bag.expirationDate).day ?? 0
    }
    private var urgencyColor: Color {
        daysLeft <= 3 ? .milkDanger : daysLeft <= 7 ? .milkWarn : .milkIndigo
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(urgencyColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                let seq = StashService.sequenceLabel(for: bag, in: allBags)
                Text(DateFormatter.freeze.string(from: bag.freezeDate))
                    .font(.subheadline.weight(.semibold))
                if !seq.isEmpty {
                    Text(seq).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s") · \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit)) each")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.subheadline.weight(.medium))
                Text(daysLeft <= 0 ? "Today!" : "\(daysLeft)d left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(urgencyColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct RecentBagRow: View {
    let bag: MilkBag
    let preferredUnit: MilkUnit

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.milkIndigo.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "snowflake")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.milkIndigo)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatter.freeze.string(from: bag.freezeDate))
                    .font(.subheadline.weight(.semibold))
                Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s") · \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit)) each")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !bag.location.isEmpty {
                    Text(bag.location + (bag.slotBin.isEmpty ? "" : " · \(bag.slotBin)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.milkIndigo)
                if bag.isExpiringSoon(within: 14) {
                    Text("Exp soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.milkWarn)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .foregroundStyle(color)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

#Preview {
    HomeView()
        .modelContainer(PreviewData.container())
}
