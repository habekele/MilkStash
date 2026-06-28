// PreviewData.swift

import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static func container(mode: JourneyMode = .building) -> ModelContainer {
        let schema = Schema([MilkBag.self, AppSettings.self, UsageEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        populate(container.mainContext, mode: mode)
        return container
    }

    static func populate(_ ctx: ModelContext, mode: JourneyMode = .building) {
        let settings = AppSettings()
        settings.journeyMode = mode
        if mode != .building {
            // Anything past building has, by definition, reached the goal at least once.
            settings.goalEverReached = true
            settings.lastCelebratedGoalDate = settings.goalStartDate
        }
        ctx.insert(settings)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func freeze(_ daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: today)!
        }
        func expire(_ fromFreeze: Date, months: Int = 6) -> Date {
            cal.date(byAdding: .month, value: months, to: fromFreeze)!
        }

        // (volumePerBag, unit, count, freezeDaysAgo, location, bin)
        let bags: [(Double, MilkUnit, Int, Int, String, String)] = [
            (4.5, .oz, 6, 180, "Deep Freezer", "Bin A"),
            (5.0, .oz, 4, 180, "Deep Freezer", "Bin A"),
            (3.0, .oz, 8, 120, "Deep Freezer", "Bin B"),
            (6.0, .oz, 3, 90,  "Fridge Freezer", "Top"),
            (4.0, .oz, 5, 90,  "Fridge Freezer", "Top"),
            (5.5, .oz, 4, 60,  "Fridge Freezer", "Middle"),
            (4.0, .oz, 6, 45,  "Deep Freezer", "Bin C"),
            (3.5, .oz, 3, 30,  "Fridge Freezer", "Bottom"),
            (5.0, .oz, 5, 15,  "Deep Freezer", "Bin C"),
            (6.0, .oz, 2, 5,   "Fridge Freezer", "Top"),
        ]

        for (vol, unit, count, daysAgo, loc, bin) in bags {
            let fd = freeze(daysAgo)
            let bag = MilkBag(
                volumePerBag: vol,
                unit: unit,
                milkBagCount: count,
                freezeDate: fd,
                expirationDate: expire(fd),
                location: loc,
                slotBin: bin
            )
            ctx.insert(bag)
        }

        // One expiring soon (within 7 days)
        let nearExpiry = MilkBag(
            volumePerBag: 4.0,
            unit: .oz,
            milkBagCount: 3,
            freezeDate: freeze(175),
            expirationDate: cal.date(byAdding: .day, value: 4, to: today)!,
            location: "Deep Freezer",
            slotBin: "Bin A"
        )
        ctx.insert(nearExpiry)

        // Sample usage history (used + discarded) across a few days
        func at(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let events: [UsageEvent] = [
            UsageEvent(
                kind: .used,
                timestamp: at(0, hour: 8, minute: 15),
                totalBags: 2, totalVolumeOz: 9.0, unit: .oz,
                lines: [
                    UsageLineSnapshot(labelCode: "A-12", freezeDate: freeze(180), milkBags: 1, volumeOz: 4.5),
                    UsageLineSnapshot(labelCode: "A-13", freezeDate: freeze(180), milkBags: 1, volumeOz: 4.5),
                ]
            ),
            UsageEvent(
                kind: .used,
                timestamp: at(0, hour: 13, minute: 40),
                totalBags: 1, totalVolumeOz: 3.0, unit: .oz,
                lines: [UsageLineSnapshot(labelCode: "B-04", freezeDate: freeze(120), milkBags: 1, volumeOz: 3.0)]
            ),
            UsageEvent(
                kind: .discarded,
                timestamp: at(1, hour: 19, minute: 5),
                totalBags: 2, totalVolumeOz: 8.0, unit: .oz,
                lines: [UsageLineSnapshot(labelCode: "C-07", freezeDate: freeze(200), milkBags: 2, volumeOz: 8.0)]
            ),
            UsageEvent(
                kind: .used,
                timestamp: at(3, hour: 7, minute: 30),
                totalBags: 3, totalVolumeOz: 15.0, unit: .oz,
                lines: [UsageLineSnapshot(labelCode: "Top", freezeDate: freeze(90), milkBags: 3, volumeOz: 15.0)]
            ),
        ]
        for e in events { ctx.insert(e) }

        try? ctx.save()
    }
}
