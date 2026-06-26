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

enum UsageKind: String, Codable, CaseIterable {
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

    // How many individual milk bags are in this Ziplock
    var milkBagCount: Int = 1

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

    var totalVolumeOz: Double {
        Double(milkBagCount) * volumePerBagOz
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

// MARK: - Usage History

/// Immutable snapshot of one Ziplock involved in a usage event. Stored by value
/// (not as a relationship to MilkBag) so history survives if the bag is later
/// deleted from inventory.
struct UsageLineSnapshot: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bagId: UUID = UUID()
    var labelCode: String = ""
    var freezeDate: Date = Date()
    var milkBags: Int = 0
    var volumeOz: Double = 0
}

/// A single recorded use-session or discard. Written at confirm time so the user
/// can look back at where their milk went.
@Model
final class UsageEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var kindRaw: String = UsageKind.used.rawValue
    var totalBags: Int = 0
    var totalVolumeOz: Double = 0
    var displayUnit: String = MilkUnit.oz.rawValue
    var notes: String = ""

    /// JSON-encoded `[UsageLineSnapshot]`. Events are immutable, so a blob avoids
    /// a second @Model + CloudKit relationship.
    var linesData: Data = Data()

    init(
        kind: UsageKind,
        timestamp: Date = Date(),
        totalBags: Int,
        totalVolumeOz: Double,
        unit: MilkUnit,
        lines: [UsageLineSnapshot],
        notes: String = ""
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.totalBags = totalBags
        self.totalVolumeOz = totalVolumeOz
        self.displayUnit = unit.rawValue
        self.notes = notes
        self.lines = lines
    }

    var kind: UsageKind {
        get { UsageKind(rawValue: kindRaw) ?? .used }
        set { kindRaw = newValue.rawValue }
    }

    var unit: MilkUnit {
        get { MilkUnit(rawValue: displayUnit) ?? .oz }
        set { displayUnit = newValue.rawValue }
    }

    var lines: [UsageLineSnapshot] {
        get { (try? JSONDecoder().decode([UsageLineSnapshot].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
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
        Double(goalMonths) * 30.0 * effectiveDailyOzGoal
    }

    var preferredUnit: MilkUnit {
        get { MilkUnit(rawValue: preferredUnitRaw) ?? .oz }
        set { preferredUnitRaw = newValue.rawValue }
    }

    /// Canonical oz/day value used throughout the app.
    /// Older builds stored raw user input, so this resolves legacy mL entries
    /// without rewriting persisted data during upgrade.
    var effectiveDailyOzGoal: Double {
        if LegacySettingsCompatibility.shouldInterpretDailyGoalAsLegacyML(self) {
            return UnitConversion.convert(dailyOzGoal, from: .mL, to: .oz)
        }
        return dailyOzGoal
    }

    /// Canonical oz threshold used for low-stash checks.
    var effectiveLowStashThresholdOz: Double {
        if LegacySettingsCompatibility.shouldInterpretLowThresholdAsLegacyML(self) {
            return UnitConversion.convert(lowStashThresholdOz, from: .mL, to: .oz)
        }
        return lowStashThresholdOz
    }

    var dailyGoalDisplayValue: Double {
        UnitConversion.convert(effectiveDailyOzGoal, from: .oz, to: preferredUnit)
    }

    var lowStashThresholdDisplayValue: Double {
        UnitConversion.convert(effectiveLowStashThresholdOz, from: .oz, to: preferredUnit)
    }

    func setDailyGoalFromDisplayValue(_ value: Double) {
        let canonicalThresholdOz = effectiveLowStashThresholdOz
        dailyOzGoal = UnitConversion.convert(value, from: preferredUnit, to: .oz)
        lowStashThresholdOz = canonicalThresholdOz
        LegacySettingsCompatibility.markCanonicalStorageEnabled()
    }

    func setLowStashThresholdFromDisplayValue(_ value: Double) {
        let canonicalDailyGoalOz = effectiveDailyOzGoal
        dailyOzGoal = canonicalDailyGoalOz
        lowStashThresholdOz = UnitConversion.convert(value, from: preferredUnit, to: .oz)
        LegacySettingsCompatibility.markCanonicalStorageEnabled()
    }
}

// MARK: - Unit Conversion

private enum LegacySettingsCompatibility {
    private static let canonicalStorageKey = "app_settings_canonical_oz_v1"

    static func shouldInterpretDailyGoalAsLegacyML(_ settings: AppSettings) -> Bool {
        guard !isCanonicalStorageEnabled else { return false }

        // Daily intake above ~80 oz/day is implausible and strongly suggests
        // a legacy mL value from older builds.
        return settings.dailyOzGoal > 80
    }

    static func shouldInterpretLowThresholdAsLegacyML(_ settings: AppSettings) -> Bool {
        guard !isCanonicalStorageEnabled else { return false }

        // If the daily goal clearly looks like a legacy mL value, treat the
        // paired threshold the same way. Otherwise only infer legacy mL when
        // the user is still in mL mode and the threshold is unusually large.
        if shouldInterpretDailyGoalAsLegacyML(settings) {
            return true
        }

        return settings.preferredUnit == .mL && settings.lowStashThresholdOz > 160
    }

    static var isCanonicalStorageEnabled: Bool {
        UserDefaults.standard.bool(forKey: canonicalStorageKey)
    }

    static func markCanonicalStorageEnabled() {
        UserDefaults.standard.set(true, forKey: canonicalStorageKey)
    }
}

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
