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
    private var days: Double      { vm.daysWorth(stashBags, dailyOz: appSettings.effectiveDailyOzGoal) }
    private var ziplocks: Int     { vm.ziplockCount(stashBags) }
    private var milkBags: Int     { vm.totalMilkBagCount(stashBags) }

    // weekly delta (approx: oz added in the last 7 days)
    private var weeklyDeltaOz: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return stashBags.filter { $0.freezeDate >= cutoff }.map(\.totalVolumeOz).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerArea
                    heroCard
                    if totalOz > 0 && totalOz < appSettings.effectiveLowStashThresholdOz {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ffButter)
                            Text("Stash is running low — \(UnitConversion.formatted(totalOz, in: unit)) remaining, below your \(UnitConversion.formatted(appSettings.effectiveLowStashThresholdOz, in: unit)) alert.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.ffInk2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ffButterSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ffButter.opacity(0.25), lineWidth: 0.5))
                    }
                    if weeklyDeltaOz > 0 {
                        FFEncouragement(
                            message: "You're up \(UnitConversion.formatted(weeklyDeltaOz, in: unit)) this week. Steady and strong."
                        )
                    }
                    quickActionsRow
                    atAGlanceSection
                    useSoonSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 100)   // room for floating tab bar
            }
            .background(Color.ffBg.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAddBag)  { AddEditBagView(bag: nil) }
        .sheet(isPresented: $showUseMilk) { UseMilkView() }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FFEyebrow(text: dateHeader)
                Spacer()
                Button {
                    // bell action — placeholder
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.ffInk3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }
            Text("Hello, friend")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)

            FFEyebrow(text: "YOUR STASH TODAY")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ffTerra)
                    Text("Your stash · \(String(format: "%.1f", days)) days")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ffInk2)
                }

                // Big serif oz number
                Text(UnitConversion.formatted(totalOz, in: unit))
                    .font(.system(size: 62, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                    .contentTransition(.numericText())

                // 14-day bar strip
                dayStripView

                // Bottom row: ziplock + bag counts
                HStack(spacing: 14) {
                    FFStatPill(value: "\(ziplocks)", label: ziplocks == 1 ? "Ziplock" : "Ziplocks", icon: "bag.fill", color: Color.ffTerra)
                    FFStatPill(value: "\(milkBags)", label: milkBags == 1 ? "Milk Bag" : "Milk Bags", icon: "drop.fill", color: Color.ffInk3)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.ffLine, lineWidth: 0.5))
        .shadow(color: Color.ffTerra.opacity(0.10), radius: 14, x: 0, y: 4)
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
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
                Spacer()
                Text("2 WEEKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ffInk3)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            // Primary: log session
            Button { showAddBag = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Log a session")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add new Ziplock")
                            .font(.system(size: 11))
                            .opacity(0.8)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.ffTerra, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            // Secondary: use milk
            Button { showUseMilk = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use milk")
                            .font(.system(size: 15, weight: .semibold))
                        Text("FIFO dispense")
                            .font(.system(size: 11))
                            .opacity(0.8)
                    }
                    Spacer()
                }
                .foregroundStyle(Color.ffTerra)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.ffSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ffLine, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - At a Glance

    private var atAGlanceSection: some View {
        let unit   = appSettings.preferredUnit
        let oldest = stashBags.filter { $0.status == .inStash }
                              .sorted { $0.freezeDate < $1.freezeDate }
                              .first
        let expiring7 = StashService.expiringSoon(bags: stashBags, within: 7).count
        let avgOz     = stashBags.isEmpty ? 0.0
                            : totalOz / Double(max(stashBags.count, 1))

        return VStack(alignment: .leading, spacing: 12) {
            FFEyebrow(text: "AT A GLANCE")

            FFCard {
                VStack(spacing: 0) {
                    FFGlanceRow(
                        icon: "calendar.badge.clock",
                        iconBg: Color.ffTerraSoft,
                        iconColor: Color.ffTerra,
                        label: "Oldest bag",
                        value: oldest.map { DateFormatter.shortDate.string(from: $0.freezeDate) } ?? "—",
                        detail: oldest.map { "\(Calendar.current.dateComponents([.day], from: $0.freezeDate, to: Date()).day ?? 0)d ago" } ?? ""
                    )
                    FFDivider().padding(.leading, 52)

                    FFGlanceRow(
                        icon: "clock.badge.exclamationmark",
                        iconBg: expiring7 > 0 ? Color.ffButterSoft : Color.ffSageSoft,
                        iconColor: expiring7 > 0 ? Color.ffButter : Color.ffSage,
                        label: "Expiring soon",
                        value: expiring7 == 0 ? "None" : "\(expiring7) bag\(expiring7 == 1 ? "" : "s")",
                        detail: "within 7 days"
                    )
                    FFDivider().padding(.leading, 52)

                    FFGlanceRow(
                        icon: "chart.bar.fill",
                        iconBg: Color.ffSurface2,
                        iconColor: Color.ffInk3,
                        label: "Avg / Ziplock",
                        value: stashBags.isEmpty ? "—" : UnitConversion.formatted(avgOz, in: unit),
                        detail: "per bag"
                    )
                }
            }
        }
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
                .frame(width: 130)
                .scaleEffect(0.9)
            }

            if expiring.isEmpty {
                FFEncouragement(
                    message: "No Ziplocks expiring within \(vm.expiringSoonFilter) days. You're on track!",
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ffInk2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ffSurface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.ffLine, lineWidth: 0.5))
    }
}

struct FFGlanceRow: View {
    let icon: String
    let iconBg: Color
    let iconColor: Color
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBg)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.ffInk2)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }
            }
        }
        .padding(.vertical, 12)
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
        HStack(spacing: 14) {
            // Calendar block
            VStack(spacing: 0) {
                Text(DateFormatter.calMonth.string(from: bag.freezeDate).uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(urgencyColor)
                Text(DateFormatter.calDay.string(from: bag.freezeDate))
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(urgencyColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(urgencyColor.opacity(0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                let seq = StashService.sequenceLabel(for: bag, in: allBags)
                if !seq.isEmpty {
                    Text(seq)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }
                Text("\(bag.milkBagCount) bag\(bag.milkBagCount == 1 ? "" : "s") · \(UnitConversion.formatted(bag.volumePerBagOz, in: preferredUnit)) each")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ffInk2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(UnitConversion.formatted(bag.totalVolumeOz, in: preferredUnit))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                Text(daysLeft <= 0 ? "TODAY" : "\(daysLeft)d left")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(urgencyColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
