// StashWidgetBridge.swift
// Publishes a summary snapshot to the App Group whenever the app backgrounds,
// and asks WidgetKit to re-render. Stash data only changes through the app,
// so a snapshot-on-background is always accurate while the app is closed.

import Foundation
import WidgetKit

enum StashWidgetBridge {
    static let appGroupID = "group.Henok.MilkStash"
    static let snapshotKey = "stash_snapshot_v1"

    static func publish(bags: [MilkBag], settings: AppSettings?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let stash = bags.filter { $0.status == .inStash }
        let totalOz = stash.map(\.totalVolumeOz).reduce(0, +)
        let bagCount = stash.map(\.milkBagCount).reduce(0, +)
        let dailyOz = settings?.effectiveDailyOzGoal ?? 25.0

        var snapshot: [String: Any] = [
            "totalOz": totalOz,
            "bricks": stash.count,
            "bags": bagCount,
            "days": dailyOz > 0 ? totalOz / dailyOz : 0,
            "unitRaw": (settings?.preferredUnit ?? .oz).rawValue,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let soonest = stash.filter({ $0.milkBagCount > 0 }).map(\.expirationDate).min() {
            snapshot["soonestExpiry"] = soonest.timeIntervalSince1970
        }
        defaults.set(snapshot, forKey: snapshotKey)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
