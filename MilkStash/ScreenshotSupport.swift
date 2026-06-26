// ScreenshotSupport.swift
// Marketing screenshot harness — only active when launched with -ScreenshotMode.

import SwiftUI
import SwiftData
import Foundation

@MainActor
enum ScreenshotData {
    static func populate(_ ctx: ModelContext) {
        let settings = AppSettings()
        settings.dailyOzGoal = 28.0
        settings.goalMonths = 3
        settings.lowStashThresholdOz = 80.0
        settings.preferredUnit = .oz
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        settings.goalStartDate = cal.date(byAdding: .day, value: -42, to: today)!
        settings.goalStartOz = 120.0
        ctx.insert(settings)

        // Realistic, photogenic stash — varied volumes, bins, freeze dates.
        // (volumePerBag, count, freezeDaysAgo, location, bin)
        let bags: [(Double, Int, Int, String, String)] = [
            (5.0, 6, 168, "Deep Freezer",   "Bin A"),
            (4.5, 5, 152, "Deep Freezer",   "Bin A"),
            (6.0, 4, 121, "Deep Freezer",   "Bin B"),
            (4.0, 8,  96, "Deep Freezer",   "Bin B"),
            (5.5, 4,  74, "Fridge Freezer", "Top"),
            (4.0, 6,  58, "Fridge Freezer", "Top"),
            (5.0, 5,  41, "Fridge Freezer", "Middle"),
            (3.5, 4,  27, "Fridge Freezer", "Middle"),
            (6.0, 3,  14, "Fridge Freezer", "Bottom"),
            (4.5, 4,   6, "Fridge Freezer", "Bottom"),
            (5.0, 2,   1, "Fridge",         "Shelf"),
        ]
        for (vol, count, daysAgo, loc, bin) in bags {
            let fd = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let exp = cal.date(byAdding: .month, value: 6, to: fd)!
            ctx.insert(MilkBag(
                volumePerBag: vol, unit: .oz, milkBagCount: count,
                freezeDate: fd, expirationDate: exp,
                location: loc, slotBin: bin
            ))
        }

        // One bag expiring in 3 days — anchors the "never waste a drop" screen.
        let oldFreeze = cal.date(byAdding: .day, value: -178, to: today)!
        ctx.insert(MilkBag(
            volumePerBag: 4.0, unit: .oz, milkBagCount: 3,
            freezeDate: oldFreeze,
            expirationDate: cal.date(byAdding: .day, value: 3, to: today)!,
            location: "Deep Freezer", slotBin: "Bin A"
        ))

        // A little usage history for the History screen.
        func at(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func freeze(_ daysAgo: Int) -> Date { cal.date(byAdding: .day, value: -daysAgo, to: today)! }

        ctx.insert(UsageEvent(
            kind: .used, timestamp: at(0, hour: 8, minute: 20),
            totalBags: 2, totalVolumeOz: 9.5, unit: .oz,
            lines: [
                UsageLineSnapshot(labelCode: "A-12", freezeDate: freeze(168), milkBags: 1, volumeOz: 5.0),
                UsageLineSnapshot(labelCode: "A-13", freezeDate: freeze(152), milkBags: 1, volumeOz: 4.5),
            ]
        ))
        ctx.insert(UsageEvent(
            kind: .used, timestamp: at(0, hour: 14),
            totalBags: 1, totalVolumeOz: 6.0, unit: .oz,
            lines: [UsageLineSnapshot(labelCode: "B-02", freezeDate: freeze(121), milkBags: 1, volumeOz: 6.0)]
        ))
        ctx.insert(UsageEvent(
            kind: .discarded, timestamp: at(2, hour: 18, minute: 30),
            totalBags: 2, totalVolumeOz: 8.0, unit: .oz,
            lines: [UsageLineSnapshot(labelCode: "C-09", freezeDate: freeze(190), milkBags: 2, volumeOz: 8.0)]
        ))

        try? ctx.save()
    }
}

struct ScreenshotHost: View {
    @State private var selectedTab: Int = sceneInitialTab()

    var body: some View {
        let scene = ProcessInfo.processInfo.environment["SCENE"]
            ?? CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") })
            ?? scenarioFromArgs()
            ?? "home"

        switch scene {
        case "stash", "inventory":
            ContentView(selectedTab: .constant(1))
        case "goal", "journey":
            ContentView(selectedTab: .constant(2))
        case "history":
            ContentView(selectedTab: .constant(3))
        case "settings":
            ContentView(selectedTab: .constant(4))
        case "addbag":
            AddEditBagView(bag: nil)
        case "feed", "use":
            UseMilkView()
        default:
            ContentView(selectedTab: .constant(0))
        }
    }

    private static func sceneInitialTab() -> Int { 0 }

    private func scenarioFromArgs() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-Scene"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
