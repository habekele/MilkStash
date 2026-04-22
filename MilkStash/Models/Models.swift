// Models.swift
// MilkStash — Breast Milk Inventory Tracker

import Foundation
import SwiftData

// MARK: - Enums

enum MilkUnit: String, Codable, CaseIterable {
    case oz = "oz"
    case mL = "mL"

    func label(plural: Bool = false) -> String { rawValue }
}

enum BagStatus: String, Codable, CaseIterable {
    case inStash   = "In Stash"
    case used      = "Used"
    case discarded = "Discarded"
}

// MARK: - MilkBag Model
// Represents one Ziplock bag containing multiple individual milk bags.

@Model
final class MilkBag {
    var id: UUID = UUID()

    // Volume per individual milk bag inside this Ziplock, stored in oz
    var volumePerBagOz: Double = 0

    // How many individual milk bags are in this Ziplock (whole bags)
    var milkBagCount: Int = 1

    // Independently tracked residual oz (from a partially used individual bag)
    // e.g. you used half of one bag — that half is tracked here separately
    var partialVolumeOz: Double = 0

    var displayUnit: String = "oz"     // "oz" or "mL" – what the user chose at entry
    var freezeDate: Date = Date()
    var expirationDate: Date = Date()
    var location: String = ""
    var slotBin: String = ""
    var labelCode: String = ""
    var notes: String = ""
    var statusRaw: String = "In Stash"

    init(
        volumePerBag: Double,
        unit: MilkUnit,
        milkBagCount: Int = 1,
        partialVolumeOz: Double = 0,
        freezeDate: Date = Date(),
        expirationDate: Date,
        location: String = "",
        slotBin: String = "",
        labelCode: String = "",
        notes: String = "",
        status: BagStatus = .inStash
    ) {
        self.id = UUID()
        self.volumePerBagOz = unit == .oz ? volumePerBag : volumePerBag / UnitConversion.mLPerOz
        self.milkBagCount = milkBagCount
        self.partialVolumeOz = partialVolumeOz
        self.displayUnit = unit.rawValue
        self.freezeDate = freezeDate
        self.expirationDate = expirationDate
        self.location = location
        self.slotBin = slotBin
        self.labelCode = labelCode
        self.notes = notes
        self.statusRaw = status.rawValue
    }

    var status: BagStatus {
        get { BagStatus(rawValue: statusRaw) ?? .inStash }
        set { statusRaw = newValue.rawValue }
    }

    var unit: MilkUnit {
        get { MilkUnit(rawValue: displayUnit) ?? .oz }
        set { displayUnit = newValue.rawValue }
    }

    /// Total oz in this Ziplock: (whole bags × volume each) + any partial remainder
    var totalVolumeOz: Double {
        Double(milkBagCount) * volumePerBagOz + partialVolumeOz
    }

    /// Total volume in a given display unit
    func totalVolumeIn(_ unit: MilkUnit) -> Double {
        UnitConversion.convert(totalVolumeOz, from: .oz, to: unit)
    }

    /// Volume per bag in a given display unit
    func volumePerBagIn(_ unit: MilkUnit) -> Double {
        UnitConversion.convert(volumePerBagOz, from: .oz, to: unit)
    }

    var isExpired: Bool {
        expirationDate < Calendar.current.startOfDay(for: Date())
    }

    func isExpiringSoon(within days: Int) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let threshold = Calendar.current.date(byAdding: .day, value: days, to: today)!
        return !isExpired && expirationDate <= threshold
    }
}

// MARK: - AppSettings Model

@Model
final class AppSettings {
    var preferredUnitRaw: String = MilkUnit.oz.rawValue
    var defaultExpirationMonths: Int = 6
    var lowStashThresholdOz: Double = 100.0
    var includeExpiredInFIFO: Bool = false
    var dailyOzGoal: Double = 25.0          // used for "days worth" calculation
    var goalMonths: Int = 3              // target supply goal in months
    var goalStartDate: Date = Date()          // when the user started tracking toward the goal
    var goalStartOz: Double = 0.0          // stash size when they started (for rate calc)

    init() {
        self.preferredUnitRaw = MilkUnit.oz.rawValue
        self.defaultExpirationMonths = 6
        self.lowStashThresholdOz = 100.0
        self.includeExpiredInFIFO = false
        self.dailyOzGoal = 25.0
        self.goalMonths = 3
        self.goalStartDate = Date()
        self.goalStartOz = 0.0
    }

    /// Target oz = goalMonths × 30 days × dailyOzGoal
    var goalTargetOz: Double {
        Double(goalMonths) * 30.0 * dailyOzGoal
    }

    var preferredUnit: MilkUnit {
        get { MilkUnit(rawValue: preferredUnitRaw) ?? .oz }
        set { preferredUnitRaw = newValue.rawValue }
    }
}

// MARK: - Unit Conversion

enum UnitConversion {
    static let mLPerOz: Double = 29.5735

    static func convert(_ value: Double, from: MilkUnit, to: MilkUnit) -> Double {
        guard from != to else { return value }
        switch (from, to) {
        case (.oz, .mL): return value * mLPerOz
        case (.mL, .oz): return value / mLPerOz
        default: return value
        }
    }

    static func formatted(_ oz: Double, in unit: MilkUnit, decimals: Int = 1) -> String {
        let val = unit == .oz ? oz : oz * mLPerOz
        return String(format: "%.\(decimals)f \(unit.rawValue)", val)
    }
}
