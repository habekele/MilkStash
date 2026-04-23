// StashService.swift

import Foundation
import SwiftData

/// Pure business logic — no UI dependencies.
struct StashService {

    // MARK: - Aggregates

    static func totalOz(bags: [MilkBag]) -> Double {
        bags.filter { $0.status == .inStash }.map(\.totalVolumeOz).reduce(0, +)
    }

    /// Total individual milk bags across all Ziplocks in stash
    static func totalMilkBagCount(bags: [MilkBag]) -> Int {
        bags.filter { $0.status == .inStash }.map(\.milkBagCount).reduce(0, +)
    }

    /// Number of Ziplock bags in stash
    static func ziplockCount(bags: [MilkBag]) -> Int {
        bags.filter { $0.status == .inStash }.count
    }

    static func daysWorth(totalOz: Double, dailyOz: Double = 25.0) -> Double {
        guard dailyOz > 0 else { return 0 }
        return totalOz / dailyOz
    }

    // MARK: - Expiration

    static func expiringSoon(bags: [MilkBag], within days: Int) -> [MilkBag] {
        bags.filter { $0.status == .inStash && $0.isExpiringSoon(within: days) }
            .sorted { $0.expirationDate < $1.expirationDate }
    }

    // MARK: - FIFO Recommendation

    static func fifoRecommendation(
        neededOz: Double,
        bags: [MilkBag],
        includeExpired: Bool
    ) -> [FIFOItem] {
        let eligible = bags
            .filter { $0.status == .inStash }
            .filter { includeExpired || !$0.isExpired }
            .sorted {
                if $0.freezeDate != $1.freezeDate { return $0.freezeDate < $1.freezeDate }
                return $0.expirationDate < $1.expirationDate
            }

        var remaining = neededOz
        var result: [FIFOItem] = []

        for ziplock in eligible {
            guard remaining > 0 else { break }
            // Bags must be thawed whole — round up to cover the remaining need
            let bagsNeeded = min(
                Int(ceil(remaining / ziplock.volumePerBagOz)),
                ziplock.milkBagCount
            )
            let takeOz = Double(bagsNeeded) * ziplock.volumePerBagOz
            result.append(FIFOItem(bag: ziplock, takeOz: takeOz, wholeMilkBags: bagsNeeded))
            remaining -= takeOz
        }

        return result
    }

    // MARK: - Ziplock Sequence Label

    static func sequenceLabel(for bag: MilkBag, in bags: [MilkBag]) -> String {
        let cal = Calendar.current
        let same = bags
            .filter { $0.status == .inStash }
            .filter { cal.isDate($0.freezeDate, inSameDayAs: bag.freezeDate) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        if same.count <= 1 { return "" }
        let idx = (same.firstIndex(where: { $0.id == bag.id }) ?? 0) + 1
        return "Ziplock \(idx) of \(same.count)"
    }

    // MARK: - Apply Use

    static func applyUse(plan: [FIFOItem], context: ModelContext) throws {
        for item in plan {
            item.bag.milkBagCount -= item.wholeMilkBags
            if item.bag.milkBagCount <= 0 {
                item.bag.milkBagCount = 0
                item.bag.status = .used
            }
        }
        try context.save()
    }

    // MARK: - Expiration date helper

    static func expirationDate(from freezeDate: Date, months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: freezeDate) ?? freezeDate
    }
}

// MARK: - FIFOItem

struct FIFOItem: Identifiable {
    let id = UUID()
    let bag: MilkBag
    let takeOz: Double
    let wholeMilkBags: Int

    var isWholeZiplock: Bool { wholeMilkBags >= bag.milkBagCount }

    func takeDescription(unit: MilkUnit) -> String {
        let bagStr = "\(wholeMilkBags) milk bag\(wholeMilkBags == 1 ? "" : "s")"
        return "\(bagStr) (\(UnitConversion.formatted(takeOz, in: unit)))"
    }
}
