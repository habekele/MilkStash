// GoalView.swift
// The "Journey" tab — set a supply goal in months, see days until you hit it.

import SwiftUI
import SwiftData

struct GoalView: View {
    @Query private var settings: [AppSettings]
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]
    @Query private var allBags: [MilkBag]
    @Environment(\.modelContext) private var context

    private var s: AppSettings { settings.first ?? AppSettings() }

    @State private var editingGoal = false
    @State private var draftMonths = 3

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

    private var dailyBuildRate: Double {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentBags = allBags.filter { $0.freezeDate >= twoWeeksAgo }

        if !recentBags.isEmpty {
            let recentOz = recentBags.map(\.totalVolumeOz).reduce(0, +)
            return recentOz / 14.0
        }

        guard !allBags.isEmpty,
              let oldestDate = allBags.map(\.freezeDate).min() else { return 0 }
        let totalDays = max(cal.dateComponents([.day], from: oldestDate, to: Date()).day ?? 30, 30)
        let totalFrozenOz = allBags.map(\.totalVolumeOz).reduce(0, +)
        return totalFrozenOz / Double(totalDays)
    }

    private var weeklyBuildRate: Double { dailyBuildRate * 7.0 }

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
            (1,                           "First Ziplock frozen"),
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
                    progressArcCard
                    FFEncouragement(
                        message: isGoalReached
                            ? "Goal reached! Your baby is well stocked."
                            : "Every session counts. You're building something wonderful."
                    )
                    buildRateSection
                    milestonesSection
                    goalAdjustPanel
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.tabBarClearance)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $editingGoal) {
                GoalSetupSheet(
                    currentMonths: s.goalMonths,
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
                draftMonths = s.goalMonths
                if s.goalMonths == 3 && s.goalStartOz == 0 && stashBags.isEmpty {
                    editingGoal = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            FFEyebrow(text: "BUILDING TOWARD \(s.goalMonths) MONTHS")
            Text("Your journey")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
                    draftMonths = s.goalMonths
                    editingGoal = true
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

#Preview {
    GoalView()
        .modelContainer(PreviewData.container())
}
