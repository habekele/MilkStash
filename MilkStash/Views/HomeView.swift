// HomeView.swift

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]

    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    @Query(filter: #Predicate<UsageEvent> { $0.kindRaw == "Used" },
           sort: \UsageEvent.timestamp, order: .reverse)
    private var recentUsed: [UsageEvent]

    /// Invoked by the "See all" button to jump to the History tab.
    var onShowHistory: (() -> Void)? = nil

    @State private var vm = HomeViewModel()
    @State private var showAddBag = false
    @State private var showUseMilk = false
    @State private var showAlerts = false

    // MARK: - Date header helpers
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let dateHeaderFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private var dateHeader: String {
        let day  = Self.dayFormatter.string(from: Date()).uppercased()
        let date = Self.dateHeaderFormatter.string(from: Date()).uppercased()
        return "\(day) · \(date)"
    }

    // MARK: - Derived values
    private var totalOz: Double   { vm.totalOz(stashBags) }
    private var unit: MilkUnit    { appSettings.preferredUnit }
    // Once the goal's been reached and there's real usage, "days of stash" is
    // driven by observed consumption so Home agrees with the Journey drawdown
    // card. Before then (still building), fall back to the planned goal rate.
    private var days: Double {
        let observed = StashService.consumptionRate(events: recentUsed, over: 14)
        let rate = (appSettings.goalEverReached && observed > 0.01)
            ? observed
            : appSettings.effectiveDailyOzGoal
        return vm.daysWorth(stashBags, dailyOz: rate)
    }
    private var ziplocks: Int     { vm.ziplockCount(stashBags) }
    private var milkBags: Int     { vm.totalMilkBagCount(stashBags) }

    // weekly delta (approx: oz added in the last 7 days)
    private var weeklyDeltaOz: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return stashBags.filter { $0.freezeDate >= cutoff }.map(\.totalVolumeOz).reduce(0, +)
    }

    // Oldest in-stash Ziplock (surfaced in the hero footer)
    private var oldestBag: MilkBag? {
        stashBags.filter { $0.status == .inStash }
                 .sorted { $0.freezeDate < $1.freezeDate }
                 .first
    }
    private var oldestBagAge: String {
        guard let oldest = oldestBag else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: oldest.freezeDate, to: Date()).day ?? 0
        return "\(days)d"
    }

    // Actionable alerts surfaced via the bell
    private var lowStash: Bool {
        totalOz > 0 && totalOz < appSettings.effectiveLowStashThresholdOz
    }
    private var hasAlerts: Bool {
        lowStash || !StashService.expiringSoon(bags: stashBags, within: 7).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    headerArea
                    heroCard
                    quickActionsRow
                    if totalOz > 0 && totalOz < appSettings.effectiveLowStashThresholdOz {
                        HStack(spacing: Space.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.ff(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ffButter)
                            Text("Stash is running low — \(UnitConversion.formatted(totalOz, in: unit)) remaining, below your \(UnitConversion.formatted(appSettings.effectiveLowStashThresholdOz, in: unit)) alert.")
                                .font(.ff(size: 14, weight: .regular))
                                .foregroundStyle(Color.ffInk2)
                        }
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ffButterSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.ffButter.opacity(0.25), lineWidth: 0.5))
                    }
                    if weeklyDeltaOz > 0 {
                        FFEncouragement(
                            message: "You're up \(UnitConversion.formatted(weeklyDeltaOz, in: unit)) this week. Steady and strong."
                        )
                    }
                    useSoonSection
                    recentlyUsedSection
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.tabBarClearance)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .tracksTabBar()
            .navigationBarHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: ExpiryNotifications.openUseMilk)) { _ in
            showUseMilk = true
        }
        .sheet(isPresented: $showAddBag)  { AddEditBagView(bag: nil) }
        .sheet(isPresented: $showUseMilk) { UseMilkView() }
        .sheet(isPresented: $showAlerts) {
            AlertsSheet(onUseMilk: {
                showAlerts = false
                // Give the alerts sheet a beat to tear down before presenting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showUseMilk = true
                }
            })
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FFEyebrow(text: dateHeader)
                Spacer()
                Button {
                    showAlerts = true
                } label: {
                    Image(systemName: hasAlerts ? "bell.badge.fill" : "bell")
                        .font(.ff(size: 16, weight: .regular))
                        .foregroundStyle(hasAlerts ? Color.ffTerra : Color.ffInk3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasAlerts ? "Alerts, action needed" : "Alerts")
            }
            Text("Hello, friend")
                .font(.ff(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            // Base warm gradient
            LinearGradient(
                colors: [Color.ffSurface, Color.ffSurface2],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Terracotta radial top-right accent
            RadialGradient(
                colors: [Color.ffTerra.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 180
            )

            // Butter soft accent bottom-left
            RadialGradient(
                colors: [Color.ffButter.opacity(0.14), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 140
            )

            // Content
            VStack(alignment: .leading, spacing: 18) {
                // Label + snowflake
                HStack(spacing: 6) {
                    Image(systemName: "snowflake")
                        .font(.ff(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ffTerra)
                    Text("Your stash · about \(Int(days.rounded())) day\(Int(days.rounded()) == 1 ? "" : "s")")
                        .font(.ff(size: 13, weight: .medium))
                        .foregroundStyle(Color.ffInk2)
                }

                // Big serif oz number
                Text(UnitConversion.formatted(totalOz, in: unit))
                    .font(.ff(size: 62, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                    .contentTransition(.numericText())

                // 14-day bar strip
                dayStripView

                // Bottom row: ziplock + bag counts + oldest
                heroStatPills
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
        .overlay(RoundedRectangle(cornerRadius: Radius.hero).stroke(Color.ffLine, lineWidth: 0.5))
        .shadow(color: Color.ffTerra.opacity(0.10), radius: 14, x: 0, y: 4)
    }

    // Hero footer stat pills — Ziplocks · Milk Bags · Oldest.
    // Falls back to two rows on narrow widths / long mL values so nothing clips.
    private var heroStatPills: some View {
        let ziplockPill = FFStatPill(value: "\(ziplocks)", label: ziplocks == 1 ? "Brick" : "Bricks", icon: "bag.fill", color: Color.ffTerra)
        let bagPill     = FFStatPill(value: "\(milkBags)", label: milkBags == 1 ? "Milk Bag" : "Milk Bags", icon: "drop.fill", color: Color.ffInk3)
        let oldestPill  = FFStatPill(value: oldestBagAge, label: "oldest", icon: "calendar.badge.clock", color: Color.ffInk3)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                ziplockPill; bagPill; oldestPill
            }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) { ziplockPill; bagPill }
                oldestPill
            }
        }
    }

    // 14-day bar strip visualization
    private var dayStripView: some View {
        let cappedDays = min(Int(days), 14)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(idx < cappedDays ? Color.ffTerra : Color.ffLine)
                        .frame(height: 18)
                }
            }
            HStack {
                Text("TODAY")
                    .font(.ff(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ffInk2)
                Spacer()
                Text("2 WEEKS")
                    .font(.ff(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ffInk2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roughly \(Int(days.rounded())) of the next 14 days covered at your current pace")
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        GeometryReader { geo in
            let buttonWidth = (geo.size.width - Space.m) / 2
            HStack(spacing: Space.m) {
                quickActionButton(
                    icon: "plus.circle.fill",
                    title: "Add to stash",
                    subtitle: "Log pumped milk",
                    style: .primary
                ) { showAddBag = true }
                .frame(width: buttonWidth)

                quickActionButton(
                    icon: "drop.fill",
                    title: "Use milk",
                    subtitle: "Oldest milk first",
                    style: .secondary
                ) { showUseMilk = true }
                .frame(width: buttonWidth)
            }
        }
        .frame(height: 72)
    }

    private enum QuickActionStyle { case primary, secondary }

    @ViewBuilder
    private func quickActionButton(
        icon: String,
        title: String,
        subtitle: String,
        style: QuickActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.ff(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.ff(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.ff(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(style == .primary ? Color.white : Color.ffTerra)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                style == .primary ? Color.ffTerra : Color.ffSurface,
                in: RoundedRectangle(cornerRadius: Radius.l)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l)
                    .stroke(style == .primary ? Color.clear : Color.ffLine, lineWidth: 0.5)
            )
        }
        .buttonStyle(.ffPressable)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Use Soon Section

    private var useSoonSection: some View {
        let expiring = vm.expiringSoon(stashBags)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                FFEyebrow(text: "USE FIRST")
                Spacer()
                Picker("Within", selection: $vm.expiringSoonFilter) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if expiring.isEmpty {
                FFEncouragement(
                    message: "No Bricks expiring within \(vm.expiringSoonFilter) days. You're on track!",
                    icon: "checkmark.seal.fill"
                )
            } else {
                FFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(expiring.enumerated()), id: \.element.id) { idx, bag in
                            FFExpiringRow(bag: bag, allBags: stashBags, preferredUnit: appSettings.preferredUnit)
                            if idx < expiring.count - 1 {
                                FFDivider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Recently Used

    @ViewBuilder
    private var recentlyUsedSection: some View {
        let recent = Array(recentUsed.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    FFEyebrow(text: "RECENTLY USED")
                    Spacer()
                    if let onShowHistory {
                        Button { onShowHistory() } label: {
                            Text("See all")
                                .font(.ff(size: 13, weight: .medium))
                                .foregroundStyle(Color.ffTerra)
                        }
                        .buttonStyle(.plain)
                    }
                }

                FFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { idx, event in
                            FFRecentUsedRow(event: event, preferredUnit: unit)
                            if idx < recent.count - 1 {
                                FFDivider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Supporting views

struct FFStatPill: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("\(value) \(label)")
                .font(.ff(size: 12, weight: .medium))
                .foregroundStyle(Color.ffInk2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ffSurface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.ffLine, lineWidth: 0.5))
    }
}

struct FFExpiringRow: View {
    let bag: MilkBag
    let allBags: [MilkBag]
    let preferredUnit: MilkUnit

    private var daysLeft: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: bag.expirationDate).day ?? 0
    }
    private var urgencyColor: Color {
        daysLeft <= 3 ? Color.milkDanger : daysLeft <= 7 ? Color.ffButter : Color.ffTerra
    }

    var body: some View {
        HStack(spacing: Space.m) {
            // Calendar block
            VStack(spacing: 0) {
                Text(DateFormatter.calMonth.string(from: bag.freezeDate).uppercased())
                    .font(.ff(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(urgencyColor)
                Text(DateFormatter.calDay.string(from: bag.freezeDate))
                    .font(.ff(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(urgencyColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(urgencyColor.opacity(0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                let seq = StashService.sequenceLabel(for: bag, in: allBags)
                if !seq.isEmpty {
                    Text(seq)
                        .font(.ff(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }
                Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s") · \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit)) each")
                    .font(.ff(size: 13))
                    .foregroundStyle(Color.ffInk2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.ff(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                Text(daysLeft <= 0 ? "TODAY" : "\(daysLeft)d left")
                    .font(.ff(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(urgencyColor)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

struct FFRecentUsedRow: View {
    let event: UsageEvent
    let preferredUnit: MilkUnit

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: IconTile.radius)
                    .fill(Color.ffSageSoft)
                    .frame(width: IconTile.size, height: IconTile.size)
                Image(systemName: "drop.fill")
                    .font(.ff(size: IconTile.iconPt, weight: .semibold))
                    .foregroundStyle(Color.ffSage)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(UnitConversion.formatted(event.totalVolumeOz, in: preferredUnit))
                    .font(.ff(size: 15, weight: .medium))
                    .foregroundStyle(Color.ffInk)
                Text("\(event.totalBags) bag\(event.totalBags == 1 ? "" : "s")")
                    .font(.ff(size: 12))
                    .foregroundStyle(Color.ffInk3)
            }

            Spacer()

            Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: Date()))
                .font(.ff(size: 13))
                .foregroundStyle(Color.ffInk3)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

#Preview {
    HomeView()
        .modelContainer(PreviewData.container())
}
