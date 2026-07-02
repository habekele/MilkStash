// ExpiryNotifications.swift
// Local "use soon" reminders, scheduled from the current stash whenever the
// app backgrounds. Stash data only changes through the app, so the pending
// set is always accurate while the app is closed.

import Foundation
import UserNotifications

enum ExpiryNotifications {
    private static let identifierPrefix = "expiry-"
    private static let askedKey = "expiry_notifications_asked_v1"

    /// Posted when the user taps an expiry notification — Home opens Use Milk.
    static let openUseMilk = Notification.Name("ffOpenUseMilk")

    /// Plain-data snapshot so scheduling can hop queues without touching models.
    struct Item: Sendable {
        let id: UUID
        let bagCount: Int
        let totalOz: Double
        let expires: Date
    }

    /// Contextual ask: called right after the user saves their first Brick,
    /// when a reminder about that Brick is an obvious next benefit.
    static func requestAuthorizationIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Rebuild all pending expiry reminders from the current stash.
    static func refresh(bags: [MilkBag]) {
        let items = bags
            .filter { $0.status == .inStash && $0.milkBagCount > 0 }
            .map { Item(id: $0.id, bagCount: $0.milkBagCount, totalOz: $0.totalVolumeOz, expires: $0.expirationDate) }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            center.getPendingNotificationRequests { pending in
                let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: ours)
                schedule(items, center: center)
            }
        }
    }

    private static func schedule(_ items: [Item], center: UNUserNotificationCenter) {
        let cal = Calendar.current
        let now = Date()

        for item in items where item.expires > now {
            // A week's warning, or tomorrow morning if the milk is closer than that.
            var fireDay = cal.date(byAdding: .day, value: -7, to: item.expires) ?? item.expires
            if fireDay <= now {
                guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
                      tomorrow < item.expires else { continue }
                fireDay = tomorrow
            }
            var comps = cal.dateComponents([.year, .month, .day], from: fireDay)
            comps.hour = 9

            let content = UNMutableNotificationContent()
            content.title = "Use this milk soon"
            let bags = "\(item.bagCount) bag\(item.bagCount == 1 ? "" : "s")"
            let oz = String(format: "%.0f oz", item.totalOz)
            content.body = "\(bags) (\(oz)) expire\(item.bagCount == 1 ? "s" : "") on \(DateFormatter.freeze.string(from: item.expires)) — oldest first."
            content.sound = .default
            content.userInfo = ["action": "useMilk"]

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(
                identifier: identifierPrefix + item.id.uuidString,
                content: content,
                trigger: trigger
            ))
        }
    }
}

/// Routes notification taps into the app (Home tab → Use Milk sheet).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func attach() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["action"] as? String == "useMilk" {
            await MainActor.run {
                NotificationCenter.default.post(name: ExpiryNotifications.openUseMilk, object: nil)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
