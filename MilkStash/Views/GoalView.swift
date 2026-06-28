// GoalView.swift
// The "Journey" tab — set a supply goal in months, see days until you hit it.

import SwiftUI
import SwiftData

struct GoalView: View {
    @Query private var settings: [AppSettings]
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]
    @Query private var allBags: [MilkBag]
    @Query private var usageEvents: [UsageEvent]
    @Environment(\.modelContext) private var context

    private var s: AppSettings { settings.first ?? AppSettings() }
    private var mode: JourneyMode { s.journeyMode }

    @State private var editingGoal = false
    @State private var setupInitialMonths = 3
    @State private var showDrawdownNudge = true

    // MARK: - Derived numbers

    private var currentOz: Double {
        stashBags.map(\.totalVolumeOz).reduce(0, +)
    }

    private var targetOz: Double { s.goalTargetOz }

    private var progress: Double {
        guard targetOz > 0 else { return 0 }
        return min(currentOz / targetOz, 1.0)
    }

    private var ozRemaining: Double { max(targetOz - currentOz, 0) }
    private var isGoalReached: Bool { currentOz >= targetOz }

    // Freeze rate (oz/day). Shares one definition with the drawdown math via StashService.
    private var dailyBuildRate: Double { StashService.buildRate(bags: allBags, over: 14) }
    private var weeklyBuildRate: Double { dailyBuildRate * 7.0 }

    // MARK: - Drawdown numbers
    private var consumptionRate: Double { StashService.consumptionRate(events: usageEvents, over: 14) }
    private var netRate: Double { StashService.netDailyRate(consumption: consumptionRate, build: dailyBuildRate) }
    private var daysRemaining: Int? { StashService.daysOfStashRemaining(currentOz: currentOz, netDailyRate: netRate) }
    private var depletionDate: Date? { StashService.projectedDepletionDate(currentOz: currentOz, netDailyRate: netRate) }

    /// Arc fill for the runway: full when holding steady, otherwise scaled to a 90-day horizon.
    private var runwayProgress: Double {
        guard let days = daysRemaining else { return 1.0 }
        return min(Double(days) / 90.0, 1.0)
    }

    /// Runway turns terracotta when the stash will cross the low-stash line within two weeks.
    private var runwayColor: Color {
        guard daysRemaining != nil else { return Color.ffSage }
        let drain = max(-netRate, 0.0001)
        let daysToLow = (currentOz - s.effectiveLowStashThresholdOz) / drain
        return daysToLow < 14 ? Color.ffTerra : Color.ffSage
    }

    /// Bricks that will expire before the stash is projected to empty — i.e. milk
    /// at risk of being lost to slow drawdown. Drives the "use oldest first" nudge.
    private var expiringBeforeEmpty: [MilkBag] {
        guard let empty = depletionDate else { return [] }
        return stashBags.filter { $0.status == .inStash && $0.expirationDate <= empty }
    }

    private var daysUntilGoal: Int? {
        guard !isGoalReached else { return 0 }
        guard dailyBuildRate > 0.01 else { return nil }
        return Int(ceil(ozRemaining / dailyBuildRate))
    }

    private var estimatedDate: Date? {
        guard let days = daysUntilGoal else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    // Last 14 days: oz per day slot (one value per day)
    private var last14DayAmounts: [Double] {
        var result = Array(repeating: 0.0, count: 14)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for bag in allBags {
            let bagDay = cal.startOfDay(for: bag.freezeDate)
            let diff = cal.dateComponents([.day], from: bagDay, to: today).day ?? 0
            if diff >= 0 && diff < 14 {
                result[13 - diff] += bag.totalVolumeOz
            }
        }
        return result
    }

    private var milestoneDefs: [(oz: Double, label: String)] {
        let defs: [(oz: Double, label: String)] = [
            (1,                           "First Brick frozen"),
            (100,                         "First 100 oz"),
            (s.effectiveDailyOzGoal * 14, "Two weeks of supply"),
            (s.effectiveDailyOzGoal * 30, "One month of supply"),
            (s.goalTargetOz / 2,          "Halfway to goal"),
            (s.goalTargetOz,              "\(s.goalMonths) months · \(String(format: "%.0f", s.goalTargetOz)) oz"),
        ]
        return defs.sorted { $0.oz < $1.oz }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xl) {
                    headerArea
                    heroSection
                    if mode == .building || mode == .maintaining {
                        FFEncouragement(message: encouragementMessage)
                        buildRateSection
                    }
                    milestonesSection
                    if mode == .building || mode == .maintaining {
                        goalAdjustPanel
                    }
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.tabBarClearance)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .tracksTabBar()
            .navigationBarHidden(true)
            .sheet(isPresented: $editingGoal) {
                GoalSetupSheet(
                    currentMonths: setupInitialMonths,
                    dailyOz: s.effectiveDailyOzGoal
                ) { months in
                    let target = settings.first ?? {
                        let fresh = AppSettings(); context.insert(fresh); return fresh
                    }()
                    target.goalMonths    = months
                    target.goalStartDate = Date()
                    target.goalStartOz   = currentOz
                    do { try context.save() } catch { print("GoalView: save failed:", error) }
                }
            }
            .onAppear {
                setupInitialMonths = s.goalMonths

                // Celebration latch: fire once per distinct goal the first time it's met.
                if let target = settings.first,
                   currentOz >= targetOz,
                   target.lastCelebratedGoalDate != target.goalStartDate {
                    target.goalEverReached = true
                    target.lastCelebratedGoalDate = target.goalStartDate
                    target.journeyMode = .celebrating
                    try? context.save()
                }

                // Onboarding auto-open only while still building.
                if s.journeyMode == .building && s.goalMonths == 3 && s.goalStartOz == 0 && stashBags.isEmpty {
                    editingGoal = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerEyebrow: String {
        switch mode {
        case .celebrating: return "YOU REACHED YOUR GOAL"
        case .maintaining: return "DRAWING DOWN YOUR STASH"
        case .complete:    return "JOURNEY COMPLETE"
        case .building:    return "BUILDING TOWARD \(s.goalMonths) MONTHS"
        }
    }

    private var encouragementMessage: String {
        switch mode {
        case .maintaining:
            return "You stocked enough to keep going — now you're drawing it down. That's exactly the plan."
        default:
            return "Every session counts. You're building something wonderful."
        }
    }

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFEyebrow(text: headerEyebrow)
            Text("Your journey")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Hero (mode-driven)

    @ViewBuilder private var heroSection: some View {
        switch mode {
        case .building:
            progressArcCard
            // Only suggest drawdown once the goal's actually been reached — a parent
            // still ramping up who logs a feed shouldn't be nudged toward "using down."
            if showDrawdownNudge, s.goalEverReached,
               StashService.suggestsDrawdown(consumption: consumptionRate, build: dailyBuildRate) {
                drawdownNudge
            }
        case .celebrating:
            celebrationCard
        case .maintaining:
            drawdownCard
            goalAchievedChip
        case .complete:
            completeCard
        }
    }

    // MARK: - Mode transitions

    private func setMode(_ newMode: JourneyMode) {
        guard let target = settings.first else { return }
        target.journeyMode = newMode
        do { try context.save() } catch { print("GoalView: setMode save failed:", error) }
    }

    private func openGoalSetup(initialMonths: Int, switchToBuilding: Bool) {
        setupInitialMonths = max(1, min(initialMonths, 12))
        if switchToBuilding { setMode(.building) }
        editingGoal = true
    }

    // MARK: - Drawdown nudge (shown in .building when use outpaces freezing)

    private var drawdownNudge: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ffTerra)
            Text("Started using your stash? Switch to the drawdown view.")
                .font(.system(size: 13))
                .foregroundStyle(Color.ffInk2)
            Spacer(minLength: 4)
            Button { setMode(.maintaining) } label: {
                Text("Switch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ffTerra)
            }
            .buttonStyle(.plain)
            Button { showDrawdownNudge = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ffInk3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.ffSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ffLine, lineWidth: 0.5))
    }

    // MARK: - Celebration Card (.celebrating)

    private var celebrationCard: some View {
        FFCard {
            VStack(spacing: 18) {
                FFEyebrow(text: "GOAL REACHED")

                ZStack {
                    FFProgressArc(progress: 1, color: Color.ffLine)
                    FFProgressArc(progress: 1, color: Color.ffSage)
                    VStack(spacing: 4) {
                        Spacer().frame(height: 52)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(Color.ffSage)
                    }
                }
                .frame(height: 180)
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("You did it")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ffInk)
                    Text("\(s.goalMonths) month\(s.goalMonths == 1 ? "" : "s") of supply, fully stocked.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ffInk2)
                        .multilineTextAlignment(.center)
                    Text("\(UnitConversion.formatted(currentOz, in: s.preferredUnit, decimals: 0)) frozen")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }

                VStack(spacing: 10) {
                    Button { openGoalSetup(initialMonths: s.goalMonths + 1, switchToBuilding: true) } label: {
                        Text("Keep building")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(Color.ffTerra, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button { setMode(.maintaining) } label: {
                        Text("Start using my stash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.ffTerra)
                            .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button { setMode(.complete) } label: {
                        Text("I'm all done")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ffInk3)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .onAppear { Haptics.success() }
    }

    // MARK: - Goal-achieved chip (shown above drawdown)

    private var goalAchievedChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.ffSage)
            Text("\(s.goalMonths)-month goal reached")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ffInk2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.ffSageSoft, in: Capsule())
    }

    // MARK: - Drawdown Card (.maintaining)

    private var drawdownCard: some View {
        FFCard {
            VStack(spacing: 16) {
                FFEyebrow(text: "STASH REMAINING")

                ZStack {
                    FFProgressArc(progress: 1, color: Color.ffLine)
                    FFProgressArc(progress: runwayProgress, color: runwayColor)
                    VStack(spacing: 4) {
                        Spacer().frame(height: 44)
                        if let days = daysRemaining {
                            Text("\(days)")
                                .font(.system(size: 48, weight: .regular, design: .serif))
                                .foregroundStyle(Color.ffInk)
                                .contentTransition(.numericText())
                            Text(days == 1 ? "day left" : "days left")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.ffInk3)
                        } else {
                            Text("Holding")
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .foregroundStyle(Color.ffInk)
                            Text("steady")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.ffInk3)
                        }
                    }
                }
                .frame(height: 180)
                .padding(.top, 12)

                if let date = depletionDate {
                    Text("On track to run out around \(DateFormatter.goalDate.string(from: date))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ffInk3)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    GoalStatCard(
                        icon: "cup.and.saucer.fill", iconColor: Color.ffTerra,
                        title: "using / day",
                        value: UnitConversion.formatted(consumptionRate, in: s.preferredUnit)
                    )
                    GoalStatCard(
                        icon: "snowflake", iconColor: Color.ffSage,
                        title: "freezing / day",
                        value: UnitConversion.formatted(dailyBuildRate, in: s.preferredUnit)
                    )
                }

                if !expiringBeforeEmpty.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ffTerra)
                        Text("\(expiringBeforeEmpty.count) brick\(expiringBeforeEmpty.count == 1 ? "" : "s") may expire before then — use oldest first.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ffInk2)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.ffTerraSoft, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Complete Card (.complete)

    private var completeCard: some View {
        FFCard {
            VStack(spacing: 18) {
                FFEyebrow(text: "JOURNEY COMPLETE")
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ffSage)

                VStack(spacing: 6) {
                    Text("Your journey, complete")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ffInk)
                    Text("You nourished your baby every step of the way.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ffInk2)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    GoalStatCard(
                        icon: "drop.fill", iconColor: Color.ffTerra,
                        title: "in stash now",
                        value: UnitConversion.formatted(currentOz, in: s.preferredUnit, decimals: 0)
                    )
                    GoalStatCard(
                        icon: "flag.checkered", iconColor: Color.ffSage,
                        title: "goal hit",
                        value: "\(s.goalMonths) mo"
                    )
                }

                Button { openGoalSetup(initialMonths: s.goalMonths, switchToBuilding: true) } label: {
                    Text("Set a new goal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ffTerra)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ffTerraSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Progress Arc Card

    private var progressArcCard: some View {
        FFCard {
            VStack(spacing: 16) {
                FFEyebrow(text: "YOU ARE HERE")

                // Semicircular arc
                ZStack {
                    FFProgressArc(progress: 1, color: Color.ffLine)
                    FFProgressArc(progress: progress, color: isGoalReached ? Color.ffSage : Color.ffTerra)

                    // Center text
                    VStack(spacing: 4) {
                        Spacer().frame(height: 44)
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 48, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ffInk)
                            .contentTransition(.numericText())
                        Text("of your goal")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.ffInk3)
                    }
                }
                .frame(height: 180)
                .padding(.top, 12)

                // Oz labels beneath arc
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UnitConversion.formatted(currentOz, in: s.preferredUnit))
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffTerra)
                        Text("current")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                    }
                    Spacer()
                    if let days = daysUntilGoal, days > 0 {
                        VStack(spacing: 2) {
                            Text("\(days)d left")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.ffInk2)
                            if let date = estimatedDate {
                                Text(DateFormatter.goalDate.string(from: date))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.ffInk3)
                            }
                        }
                    } else if isGoalReached {
                        Text("Reached!")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffSage)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UnitConversion.formatted(targetOz, in: s.preferredUnit, decimals: 0))
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.ffInk2)
                        Text("goal")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.ffInk3)
                    }
                }
            }
        }
    }

    // MARK: - Build Rate

    private var buildRateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFEyebrow(text: "LAST 14 DAYS")

            FFCard {
                VStack(alignment: .leading, spacing: 14) {
                    // Headline avg
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(UnitConversion.formatted(weeklyBuildRate, in: s.preferredUnit))
                            .font(.system(size: 32, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ffInk)
                        Text("/week avg")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ffInk3)
                        Spacer()
                        if weeklyBuildRate > 0 {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ffSage)
                        }
                    }

                    // 14-day bar chart
                    let amounts = last14DayAmounts
                    let maxAmt = amounts.max() ?? 1.0

                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(0..<14, id: \.self) { idx in
                                let ratio = maxAmt > 0 ? amounts[idx] / maxAmt : 0
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(idx == 13 ? Color.ffTerra : Color.ffTerra.opacity(0.55))
                                    .frame(height: max(CGFloat(ratio) * 60, 4))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 64)

                        HStack {
                            Text("2 WKS AGO")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.ffInk3)
                            Spacer()
                            Text("TODAY")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.ffInk3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FFEyebrow(text: "MILESTONES")

            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(milestoneDefs.enumerated()), id: \.offset) { idx, def in
                        let done = currentOz >= def.oz
                        let isCurrent = !done && (idx == 0 || currentOz >= milestoneDefs[idx - 1].oz)

                        HStack(spacing: 14) {
                            // Indicator
                            ZStack {
                                Circle()
                                    .fill(done ? Color.ffSageSoft
                                               : isCurrent ? Color.ffTerraSoft
                                               : Color.ffSurface2)
                                    .frame(width: 32, height: 32)
                                Image(systemName: done ? "checkmark" : isCurrent ? "circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(done ? Color.ffSage
                                                          : isCurrent ? Color.ffTerra
                                                          : Color.ffInk4)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(def.label)
                                        .font(.system(size: 14, weight: done ? .regular : .semibold))
                                        .foregroundStyle(done ? Color.ffInk3 : Color.ffInk)
                                        .strikethrough(done, color: Color.ffInk2)

                                    if isCurrent {
                                        Text("NEXT")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.ffTerra)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.ffTerraSoft)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(UnitConversion.formatted(def.oz, in: s.preferredUnit, decimals: 0))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.ffInk3)
                            }

                            Spacer()

                            if done {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.ffSage)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)

                        if idx < milestoneDefs.count - 1 {
                            FFDivider().padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Goal Adjust Panel

    private var goalAdjustPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    FFEyebrow(text: "YOUR GOAL")
                    Text("\(s.goalMonths) month\(s.goalMonths == 1 ? "" : "s") of supply")
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ffInk)
                    Text(UnitConversion.formatted(targetOz, in: s.preferredUnit, decimals: 0) + " target")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ffInk3)
                }

                Spacer()

                Button {
                    openGoalSetup(initialMonths: s.goalMonths, switchToBuilding: false)
                } label: {
                    Text("Adjust")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ffTerra)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ffTerraSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.ffSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.ffLine)
            )
        }
    }
}

// MARK: - Progress Arc Shape

struct FFProgressArc: View {
    var progress: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h * 0.85)
            let radius = min(w, h * 2) * 0.42
            let startAngle = Angle.degrees(180)
            let endAngle = Angle.degrees(180 + 180 * progress)

            Path { path in
                path.addArc(center: center,
                            radius: radius,
                            startAngle: startAngle,
                            endAngle: endAngle,
                            clockwise: false)
            }
            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }
    }
}

// MARK: - Goal Setup Sheet

struct GoalSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentMonths: Int
    let dailyOz: Double
    let onSave: (Int) -> Void

    @State private var selectedMonths: Int

    init(currentMonths: Int, dailyOz: Double, onSave: @escaping (Int) -> Void) {
        self.currentMonths = currentMonths
        self.dailyOz       = dailyOz
        self.onSave        = onSave
        _selectedMonths    = State(initialValue: currentMonths)
    }

    private var targetOz: Double {
        Double(selectedMonths) * 30.0 * dailyOz
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ffBg.ignoresSafeArea()

                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Color.ffTerra)
                        Text("Set Your Supply Goal")
                            .font(.system(size: 26, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ffInk)
                        Text("How many months of frozen supply do you want to build?")
                            .font(.subheadline)
                            .foregroundStyle(Color.ffInk2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 16) {
                        Text("\(selectedMonths) month\(selectedMonths == 1 ? "" : "s")")
                            .font(.system(size: 56, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ffTerra)
                            .contentTransition(.numericText())

                        Slider(value: Binding(
                            get: { Double(selectedMonths) },
                            set: { selectedMonths = Int($0) }
                        ), in: 1...12, step: 1)
                        .tint(Color.ffTerra)
                        .padding(.horizontal)

                        HStack {
                            Text("1 month").font(.caption).foregroundStyle(Color.ffInk3)
                            Spacer()
                            Text("12 months").font(.caption).foregroundStyle(Color.ffInk3)
                        }
                        .padding(.horizontal)
                    }

                    FFCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your target")
                                    .font(.caption)
                                    .foregroundStyle(Color.ffInk3)
                                Text(String(format: "%.0f oz  /  %.0f mL", targetOz, targetOz * UnitConversion.mLPerOz))
                                    .font(.system(size: 18, weight: .regular, design: .serif))
                                    .foregroundStyle(Color.ffTerra)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Formula")
                                    .font(.caption)
                                    .foregroundStyle(Color.ffInk3)
                                Text("\(selectedMonths) × 30 × \(String(format: "%.0f", dailyOz))")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.ffInk2)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Text("Based on \(String(format: "%.0f", dailyOz)) oz/day — change in Settings.")
                        .font(.caption)
                        .foregroundStyle(Color.ffInk3)

                    Spacer()

                    Button {
                        onSave(selectedMonths)
                        dismiss()
                    } label: {
                        Text("Set Goal")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background(Color.ffTerra, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ffTerra)
                }
            }
        }
    }
}

// MARK: - Supporting Views (kept for compatibility)

struct GoalStatCard: View {
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
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ffInk)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.ffInk3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.ffSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ffLine, lineWidth: 0.5))
    }
}

struct BuildRateStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.ffInk3)
        }
        .frame(maxWidth: .infinity)
    }
}

extension DateFormatter {
    static let goalDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

#Preview("Building") {
    GoalView().modelContainer(PreviewData.container())
}

#Preview("Celebrating") {
    GoalView().modelContainer(PreviewData.container(mode: .celebrating))
}

#Preview("Drawdown") {
    GoalView().modelContainer(PreviewData.container(mode: .maintaining))
}

#Preview("Complete") {
    GoalView().modelContainer(PreviewData.container(mode: .complete))
}
