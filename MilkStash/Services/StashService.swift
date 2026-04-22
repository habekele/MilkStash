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
            let takeOz = min(ziplock.totalVolumeOz, remaining)

            // Work out how many whole milk bags that corresponds to,
            // and how much partial volume is left over
            let wholeBagsNeeded = min(Int(takeOz / ziplock.volumePerBagOz), ziplock.milkBagCount)
            let wholeOz = Double(wholeBagsNeeded) * ziplock.volumePerBagOz
            let partialOz = takeOz - wholeOz  // leftover that comes from a partial bag

            result.append(FIFOItem(
                bag: ziplock,
                takeOz: takeOz,
                wholeMilkBags: wholeBagsNeeded,
                partialOz: partialOz
            ))
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
            let ziplock = item.bag

            // Subtract whole milk bags
            ziplock.milkBagCount -= item.wholeMilkBags

            // Subtract partial oz from the partial tracker
            // First consume any existing partial, then bite into a whole bag if needed
            var partialToRemove = item.partialOz
            if partialToRemove > 0 {
                if ziplock.partialVolumeOz >= partialToRemove {
                    ziplock.partialVolumeOz -= partialToRemove
                } else {
                    // Use up remaining partial, then open a whole bag
                    partialToRemove -= ziplock.partialVolumeOz
                    if ziplock.milkBagCount > 0 {
                        ziplock.milkBagCount -= 1
                        ziplock.partialVolumeOz = ziplock.volumePerBagOz - partialToRemove
                    } else {
                        ziplock.partialVolumeOz = 0
                    }
                }
            }

            // Mark Ziplock used if fully emptied
            if ziplock.milkBagCount <= 0 && ziplock.partialVolumeOz < 0.01 {
                ziplock.milkBagCount = 0
                ziplock.partialVolumeOz = 0
                ziplock.status = .used
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
    let wholeMilkBags: Int    // whole individual bags to remove
    let partialOz: Double     // any additional partial oz beyond whole bags

    var isWholeZiplock: Bool { takeOz >= bag.totalVolumeOz - 0.001 }

    /// Human-readable description of what to take
    func takeDescription(unit: MilkUnit) -> String {
        var parts: [String] = []
        if wholeMilkBags > 0 {
            parts.append("\(wholeMilkBags) milk bag\(wholeMilkBags == 1 ? "" : "s")")
        }
        if partialOz > 0.01 {
            parts.append(UnitConversion.formatted(partialOz, in: unit) + " partial")
        }
        let ozTotal = UnitConversion.formatted(takeOz, in: unit)
        return parts.joined(separator: " + ") + " (\(ozTotal))"
    }
}
