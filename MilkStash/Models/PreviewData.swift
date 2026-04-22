// PreviewData.swift

import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static func container() -> ModelContainer {
        let schema = Schema([MilkBag.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        populate(container.mainContext)
        return container
    }

    static func populate(_ ctx: ModelContext) {
        let settings = AppSettings()
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

        // One expiring soon (within 7 days), with a partial
        let nearExpiry = MilkBag(
            volumePerBag: 4.0,
            unit: .oz,
            milkBagCount: 3,
            partialVolumeOz: 2.0,
            freezeDate: freeze(175),
            expirationDate: cal.date(byAdding: .day, value: 4, to: today)!,
            location: "Deep Freezer",
            slotBin: "Bin A"
        )
        ctx.insert(nearExpiry)

        try? ctx.save()
    }
}
