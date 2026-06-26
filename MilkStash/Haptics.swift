// Haptics.swift
// Lightweight tactile feedback for the core logging loop.

import UIKit

enum Haptics {
    // Retained for the app's lifetime. A throwaway generator can be deallocated
    // before the Taptic Engine plays the haptic — which silently drops it when
    // the triggering view dismisses in the same runloop tick (e.g. save → dismiss).
    private static let notification = UINotificationFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .light)

    /// Warm up the Taptic Engine so the next haptic fires without latency or
    /// being dropped. Call from `.onAppear` of views that trigger feedback.
    static func prepare() {
        notification.prepare()
        impact.prepare()
    }

    /// A confirming tap — bag added, milk logged.
    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare() // keep warm for the next one
    }

    /// A cautionary tap — discard, delete, or a blocked save.
    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    /// A soft tick for light, frequent interactions.
    static func light() {
        impact.impactOccurred()
        impact.prepare()
    }
}
