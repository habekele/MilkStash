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

    /// FIFO that pulls a target number of whole milk bags (rather than ounces).
    static func fifoRecommendationByBags(
        neededBags: Int,
        bags: [MilkBag],
        includeExpired: Bool
    ) -> [FIFOItem] {
        guard neededBags > 0 else { return [] }
        let eligible = bags
            .filter { $0.status == .inStash && $0.milkBagCount > 0 }
            .filter { includeExpired || !$0.isExpired }
            .sorted {
                if $0.freezeDate != $1.freezeDate { return $0.freezeDate < $1.freezeDate }
                return $0.expirationDate < $1.expirationDate
            }

        var remaining = neededBags
        var result: [FIFOItem] = []
        for ziplock in eligible {
            guard remaining > 0 else { break }
            let take = min(remaining, ziplock.milkBagCount)
            let takeOz = Double(take) * ziplock.volumePerBagOz
            result.append(FIFOItem(bag: ziplock, takeOz: takeOz, wholeMilkBags: take))
            remaining -= take
        }
        return result
    }

    /// Build a plan from a manual user selection of how many bags to pull
    /// from each ziplock, sorted by freeze date ascending.
    static func manualPlan(
        selections: [UUID: Int],
        bags: [MilkBag]
    ) -> [FIFOItem] {
        let lookup = Dictionary(uniqueKeysWithValues: bags.map { ($0.id, $0) })
        var items: [FIFOItem] = []
        for (id, take) in selections where take > 0 {
            guard let bag = lookup[id] else { continue }
            let clamped = min(take, bag.milkBagCount)
            guard clamped > 0 else { continue }
            let takeOz = Double(clamped) * bag.volumePerBagOz
            items.append(FIFOItem(bag: bag, takeOz: takeOz, wholeMilkBags: clamped))
        }
        return items.sorted { $0.bag.freezeDate < $1.bag.freezeDate }
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

    static func applyUse(plan: [FIFOItem], unit: MilkUnit, context: ModelContext) throws {
        guard !plan.isEmpty else { return }

        // Record the session before mutating bags so the snapshot reflects what
        // was actually pulled.
        let lines = plan.map { item in
            UsageLineSnapshot(
                bagId: item.bag.id,
                labelCode: item.bag.labelCode,
                freezeDate: item.bag.freezeDate,
                milkBags: item.wholeMilkBags,
                volumeOz: item.takeOz
            )
        }
        let event = UsageEvent(
            kind: .used,
            totalBags: plan.map(\.wholeMilkBags).reduce(0, +),
            totalVolumeOz: plan.map(\.takeOz).reduce(0, +),
            unit: unit,
            lines: lines
        )
        context.insert(event)

        for item in plan {
            item.bag.milkBagCount -= item.wholeMilkBags
            if item.bag.milkBagCount <= 0 {
                item.bag.milkBagCount = 0
                item.bag.status = .used
            }
        }
        try context.save()
    }

    /// Mark a Ziplock as discarded and log a matching history event.
    static func discard(bag: MilkBag, unit: MilkUnit, context: ModelContext) throws {
        let line = UsageLineSnapshot(
            bagId: bag.id,
            labelCode: bag.labelCode,
            freezeDate: bag.freezeDate,
            milkBags: bag.milkBagCount,
            volumeOz: bag.totalVolumeOz
        )
        let event = UsageEvent(
            kind: .discarded,
            totalBags: bag.milkBagCount,
            totalVolumeOz: bag.totalVolumeOz,
            unit: unit,
            lines: [line]
        )
        context.insert(event)
        bag.status = .discarded
        try context.save()
    }

    // MARK: - History grouping

    /// Group usage events into day buckets (descending), each bucket's events
    /// also sorted newest-first.
    static func groupedByDay(_ events: [UsageEvent]) -> [(day: Date, events: [UsageEvent])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: events) { cal.startOfDay(for: $0.timestamp) }
        return buckets
            .map { (day: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
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
