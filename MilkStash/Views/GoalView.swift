// GoalView.swift
// The "Journey" tab — set a supply goal in months, see days until you hit it.

import SwiftUI
import SwiftData

struct GoalView: View {
    @Query private var settings: [AppSettings]
    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]
    @Environment(\.modelContext) private var context

    // Single source of truth — never recreated once inserted
    private var s: AppSettings {
        settings.first ?? ensureSettings()
    }

    @discardableResult
    private func ensureSettings() -> AppSettings {
        // Only insert if truly empty — avoids creating duplicates
        if let existing = settings.first { return existing }
        let fresh = AppSettings()
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    // Local edit state for the goal picker
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

    private var ozRemaining: Double {
        max(targetOz - currentOz, 0)
    }

    private var isGoalReached: Bool { currentOz >= targetOz }

    /// Rolling 2-week average: oz added in the last 14 days ÷ number of days with data.
    /// Falls back to all-time average if no bags were frozen in the last 14 days.
    private var dailyBuildRate: Double {
        guard !stashBags.isEmpty else { return 0 }
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentBags = stashBags.filter { $0.freezeDate >= twoWeeksAgo }

        if !recentBags.isEmpty {
            let recentOz = recentBags.map(\.totalVolumeOz).reduce(0, +)
            // Always divide by 14 — this is a 14-day rolling average.
            // Using daysSpanned (days since earliest bag) caused spikes when
            // all recent bags were added on the same day (daysSpanned = 1).
            return recentOz / 14.0
        }

        // Fallback: all-time average if nothing frozen in last 2 weeks.
        // Use a minimum of 30 days to prevent spikes when all bags share
        // the same freeze date (e.g. user entered their whole stash at once).
        guard let oldestDate = stashBags.map(\.freezeDate).min() else { return 0 }
        let totalDays = max(cal.dateComponents([.day], from: oldestDate, to: Date()).day ?? 30, 30)
        return currentOz / Double(totalDays)
    }

    /// Days until goal is reached at current build rate
    private var daysUntilGoal: Int? {
        guard !isGoalReached else { return 0 }
        guard dailyBuildRate > 0.01 else { return nil }  // nil = can't estimate
        return Int(ceil(ozRemaining / dailyBuildRate))
    }

    private var estimatedDate: Date? {
        guard let days = daysUntilGoal else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    goalHeroCard
                    statsGrid
                    buildRateCard
                    changeGoalButton
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $editingGoal) {
                GoalSetupSheet(
                    currentMonths: s.goalMonths,
                    dailyOz: s.dailyOzGoal
                ) { months in
                    // Fetch fresh from context — avoids stale closure capture
                    let descriptor = FetchDescriptor<AppSettings>()
                    let all = (try? context.fetch(descriptor)) ?? []
                    let target: AppSettings
                    if let existing = all.first {
                        target = existing
                    } else {
                        target = AppSettings()
                        context.insert(target)
                    }
                    target.goalMonths    = months
                    target.goalStartDate = Date()
                    target.goalStartOz   = currentOz
                    try? context.save()
                }
            }
            .onAppear {
                draftMonths = s.goalMonths
                // If never set up, open the sheet automatically
                if s.goalMonths == 3 && s.goalStartOz == 0 && stashBags.isEmpty {
                    editingGoal = true
                }
            }
        }
    }

    // MARK: - Hero Card

    private var goalHeroCard: some View {
        ZStack {
            LinearGradient(
                colors: isGoalReached
                    ? [Color.milkSage, Color.milkSage.opacity(0.75)]
                    : [Color.milkIndigo, Color.milkIndigo.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Decorative circles
            Circle().fill(Color.white.opacity(0.06)).frame(width: 180).offset(x: 70, y: -50)
            Circle().fill(Color.white.opacity(0.04)).frame(width: 110).offset(x: -40, y: 60)

            VStack(alignment: .leading, spacing: 20) {

                // Row 1: goal label + target badge
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isGoalReached ? "🎉 Goal Reached!" : "Supply Goal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .tracking(0.5)
                        Text("\(s.goalMonths) month\(s.goalMonths == 1 ? "" : "s") of supply")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(UnitConversion.formatted(targetOz, in: s.preferredUnit, decimals: 0))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("target")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }

                // Row 2: BIG day countdown
                if isGoalReached {
                    Text("You did it! 🥛")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else if let days = daysUntilGoal {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(days)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("days")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("until goal")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                            if let date = estimatedDate {
                                Text(DateFormatter.goalDate.string(from: date))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking…")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Add more bags so we can estimate your timeline.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                // Row 3: Progress bar
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: max(geo.size.width * progress, 14), height: 14)
                                .animation(.spring(response: 0.6), value: progress)
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        Text(UnitConversion.formatted(currentOz, in: s.preferredUnit))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Color.milkIndigo.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            GoalStatCard(
                icon: "target",
                iconColor: Color.milkCoral,
                title: "Target",
                value: UnitConversion.formatted(targetOz, in: s.preferredUnit, decimals: 0)
            )
            GoalStatCard(
                icon: "drop.fill",
                iconColor: Color.milkIndigo,
                title: "Current",
                value: UnitConversion.formatted(currentOz, in: s.preferredUnit)
            )
            GoalStatCard(
                icon: "arrow.up.circle.fill",
                iconColor: Color.milkSage,
                title: "Remaining",
                value: isGoalReached ? "Done! 🎉" : UnitConversion.formatted(ozRemaining, in: s.preferredUnit)
            )
        }
    }

    // MARK: - Build Rate Card

    private var buildRateCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Your Build Rate", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 0) {
                BuildRateStat(
                    value: dailyBuildRate > 0.01
                        ? UnitConversion.formatted(dailyBuildRate, in: s.preferredUnit)
                        : "—",
                    label: "per day"
                )
                Divider().frame(height: 60)
                BuildRateStat(
                    value: dailyBuildRate > 0.01
                        ? UnitConversion.formatted(dailyBuildRate * 7, in: s.preferredUnit)
                        : "—",
                    label: "per week"
                )
                Divider().frame(height: 60)
                BuildRateStat(
                    value: s.dailyOzGoal > 0
                        ? UnitConversion.formatted(s.dailyOzGoal, in: s.preferredUnit, decimals: 0) + "/day"
                        : "—",
                    label: "baby drinks"
                )
            }
            .padding(.vertical, 16)

            // Formula explanation
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Color.milkIndigo)
                    Text("Goal = \(s.goalMonths) mo × 30 days × \(UnitConversion.formatted(s.dailyOzGoal, in: s.preferredUnit, decimals: 0))/day = \(UnitConversion.formatted(targetOz, in: s.preferredUnit, decimals: 0))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(Color.milkIndigo)
                    let cal = Calendar.current
                    let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                    let hasRecentBags = stashBags.contains { $0.freezeDate >= twoWeeksAgo }
                    if hasRecentBags {
                        let recentOz = stashBags.filter { $0.freezeDate >= twoWeeksAgo }.map(\.totalVolumeOz).reduce(0, +)
                        Text("Rate = \(UnitConversion.formatted(recentOz, in: s.preferredUnit, decimals: 0)) added ÷ last 14 days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let oldest = stashBags.map(\.freezeDate).min() {
                        Text("Rate = \(UnitConversion.formatted(currentOz, in: s.preferredUnit, decimals: 0)) ÷ days since \(DateFormatter.goalDate.string(from: oldest)) (no recent data)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Rate calculated from recent pumping activity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.milkIndigo.opacity(0.05))
        }
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Change Goal Button

    private var changeGoalButton: some View {
        Button {
            draftMonths = s.goalMonths
            editingGoal = true
        } label: {
            Label("Change Goal", systemImage: "slider.horizontal.3")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Color.milkIndigo)
                .background(Color.milkIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.milkIndigo.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 32) {
                // Explainer
                VStack(spacing: 8) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.milkIndigo)
                    Text("Set Your Supply Goal")
                        .font(.title2.weight(.bold))
                    Text("How many months of frozen supply do you want to build?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Month picker
                VStack(spacing: 16) {
                    Text("\(selectedMonths) month\(selectedMonths == 1 ? "" : "s")")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.milkIndigo)
                        .contentTransition(.numericText())

                    Slider(value: Binding(
                        get: { Double(selectedMonths) },
                        set: { selectedMonths = Int($0) }
                    ), in: 1...12, step: 1)
                    .tint(Color.milkIndigo)
                    .padding(.horizontal)

                    HStack {
                        Text("1 month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("12 months")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Calculated target
                VStack(spacing: 12) {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your target")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f oz  /  %.0f mL",
                                        targetOz, targetOz * UnitConversion.mLPerOz))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.milkIndigo)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Formula")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(selectedMonths) × 30 × \(String(format: "%.0f", dailyOz))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    Divider()

                    Text("Based on \(String(format: "%.0f", dailyOz)) oz/day — change in Settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Save button
                Button {
                    onSave(selectedMonths)
                    dismiss()
                } label: {
                    Text("Set Goal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Color.milkIndigo, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Supporting Views

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
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
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

struct BuildRateStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
