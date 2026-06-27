// ViewModels.swift

import Foundation
import SwiftData
import Combine

// MARK: - HomeViewModel

@MainActor
@Observable
final class HomeViewModel {
    var expiringSoonFilter: Int = 7

    func totalOz(_ bags: [MilkBag]) -> Double { StashService.totalOz(bags: bags) }
    func ziplockCount(_ bags: [MilkBag]) -> Int { StashService.ziplockCount(bags: bags) }
    func totalMilkBagCount(_ bags: [MilkBag]) -> Int { StashService.totalMilkBagCount(bags: bags) }
    func daysWorth(_ bags: [MilkBag], dailyOz: Double = 25.0) -> Double { StashService.daysWorth(totalOz: totalOz(bags), dailyOz: dailyOz) }

    func expiringSoon(_ bags: [MilkBag]) -> [MilkBag] {
        StashService.expiringSoon(bags: bags, within: expiringSoonFilter)
    }
}

// MARK: - InventoryViewModel

@MainActor
@Observable
final class InventoryViewModel {
    var searchText: String = ""
    var filterLocation: String = ""
    var filterBin: String = ""
    var filterStatus: BagStatus? = .inStash
    var filterExpiringSoon: Bool = false
    var filterExpired: Bool = false
    var sortOption: SortOption = .freezeOldest

    enum SortOption: String, CaseIterable {
        case freezeOldest  = "Frozen (Oldest)"
        case freezeNewest  = "Frozen (Newest)"
        case expiration    = "Expiration"
        case volume        = "Volume"
    }

    func filtered(_ bags: [MilkBag]) -> [MilkBag] {
        var result = bags

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.location.lowercased().contains(q) ||
                $0.slotBin.lowercased().contains(q) ||
                $0.labelCode.lowercased().contains(q) ||
                $0.notes.lowercased().contains(q)
            }
        }

        if !filterLocation.isEmpty { result = result.filter { $0.location == filterLocation } }
        if !filterBin.isEmpty      { result = result.filter { $0.slotBin == filterBin } }
        if let status = filterStatus { result = result.filter { $0.status == status } }
        if filterExpiringSoon { result = result.filter { $0.isExpiringSoon(within: 30) } }
        if filterExpired      { result = result.filter { $0.isExpired } }

        switch sortOption {
        case .freezeOldest: result.sort { $0.freezeDate < $1.freezeDate }
        case .freezeNewest: result.sort { $0.freezeDate > $1.freezeDate }
        case .expiration:   result.sort { $0.expirationDate < $1.expirationDate }
        case .volume:       result.sort { $0.totalVolumeOz > $1.totalVolumeOz }
        }

        return result
    }

    func uniqueLocations(_ bags: [MilkBag]) -> [String] {
        Array(Set(bags.map(\.location).filter { !$0.isEmpty })).sorted()
    }

    func sequenceLabel(for bag: MilkBag, in bags: [MilkBag]) -> String {
        StashService.sequenceLabel(for: bag, in: bags)
    }
}

// MARK: - AddEditBagViewModel

@MainActor
@Observable
final class AddEditBagViewModel {
    var volumePerBagText: String = ""
    var milkBagCountText: String = "1"
    var unit: MilkUnit = .oz
    var freezeDate: Date = Date()
    var useCustomExpiration: Bool = false
    var expirationDate: Date = Date()
    var location: String = ""
    var slotBin: String = ""
    var labelCode: String = ""
    var notes: String = ""
    var status: BagStatus = .inStash

    var validationError: String? = nil

    var volumePerBag: Double { Double(volumePerBagText) ?? 0 }
    var milkBagCount: Int    { Int(milkBagCountText) ?? 1 }

    var computedTotalOz: Double {
        let perBagOz = unit == .oz ? volumePerBag : volumePerBag / UnitConversion.mLPerOz
        return Double(milkBagCount) * perBagOz
    }

    func load(from bag: MilkBag, settings: AppSettings) {
        unit = bag.unit
        volumePerBagText = String(format: "%.1f", bag.volumePerBagIn(bag.unit))
        milkBagCountText = "\(bag.milkBagCount)"
        freezeDate = bag.freezeDate
        useCustomExpiration = true
        expirationDate = bag.expirationDate
        location = bag.location
        slotBin = bag.slotBin
        labelCode = bag.labelCode
        notes = bag.notes
        status = bag.status
    }

    func updateExpirationIfNeeded(settings: AppSettings) {
        guard !useCustomExpiration else { return }
        expirationDate = StashService.expirationDate(from: freezeDate, months: settings.defaultExpirationMonths)
    }

    func validate() -> Bool {
        guard let vol = Double(volumePerBagText), vol > 0 else {
            validationError = "Volume per bag must be greater than 0."
            return false
        }
        guard let count = Int(milkBagCountText), count >= 1 else {
            validationError = "Bag count must be at least 1."
            return false
        }
        validationError = nil
        return true
    }

    @discardableResult
    func save(bag: MilkBag? = nil, context: ModelContext, settings: AppSettings) -> Bool {
        let expiry = useCustomExpiration
            ? expirationDate
            : StashService.expirationDate(from: freezeDate, months: settings.defaultExpirationMonths)

        if let existing = bag {
            existing.volumePerBagOz = unit == .oz ? volumePerBag : volumePerBag / UnitConversion.mLPerOz
            existing.displayUnit = unit.rawValue
            existing.milkBagCount = milkBagCount
            existing.freezeDate = freezeDate
            existing.expirationDate = expiry
            existing.location = location
            existing.slotBin = slotBin
            existing.labelCode = labelCode
            existing.notes = notes
            existing.status = status
        } else {
            let newBag = MilkBag(
                volumePerBag: volumePerBag,
                unit: unit,
                milkBagCount: milkBagCount,
                freezeDate: freezeDate,
                expirationDate: expiry,
                location: location,
                slotBin: slotBin,
                labelCode: labelCode,
                notes: notes,
                status: status
            )
            context.insert(newBag)
        }
        do {
            try context.save()
            validationError = nil
            return true
        } catch {
            validationError = "Couldn't save your changes. Please try again."
            return false
        }
    }
}

// MARK: - UseMilkViewModel

@MainActor
@Observable
final class UseMilkViewModel {
    enum SelectionMode: String, CaseIterable {
        case auto   = "Auto (FIFO)"
        case manual = "Pick yourself"
    }

    var bagCountText: String = ""
    var mode: SelectionMode = .auto
    var unit: MilkUnit = .oz
    var includeExpired: Bool = false
    var isBagFieldFocused: Bool = false

    /// Per-ziplock bag counts for manual mode, keyed by MilkBag.id
    var manualSelections: [UUID: Int] = [:]

    var recommendation: [FIFOItem] = []

    var bagsNeeded: Int { max(Int(bagCountText) ?? 0, 0) }

    func updateRecommendation(bags: [MilkBag]) {
        switch mode {
        case .auto:
            guard bagsNeeded > 0 else { recommendation = []; return }
            recommendation = StashService.fifoRecommendationByBags(
                neededBags: bagsNeeded,
                bags: bags,
                includeExpired: includeExpired
            )
        case .manual:
            recommendation = StashService.manualPlan(selections: manualSelections, bags: bags)
        }
    }

    var totalSelectedBags: Int {
        recommendation.map(\.wholeMilkBags).reduce(0, +)
    }

    var canFulfill: Bool {
        switch mode {
        case .auto:   return totalSelectedBags >= bagsNeeded && bagsNeeded > 0
        case .manual: return totalSelectedBags > 0
        }
    }

    var totalCoveredOz: Double {
        recommendation.map(\.takeOz).reduce(0, +)
    }

    func setManualBagCount(for bagID: UUID, to count: Int, in bags: [MilkBag]) {
        let clamped = max(0, count)
        if clamped == 0 {
            manualSelections.removeValue(forKey: bagID)
        } else {
            manualSelections[bagID] = clamped
        }
        updateRecommendation(bags: bags)
    }

    func manualCount(for bagID: UUID) -> Int {
        manualSelections[bagID] ?? 0
    }

    func resetManualSelections(in bags: [MilkBag]) {
        manualSelections = [:]
        updateRecommendation(bags: bags)
    }

    func applyUse(context: ModelContext) {
        try? StashService.applyUse(plan: recommendation, unit: unit, context: context)
        bagCountText = ""
        manualSelections = [:]
        recommendation = []
    }
}

// MARK: - Helpers

extension DateFormatter {
    static let freeze: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let expiry: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()
}
