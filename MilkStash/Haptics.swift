// Haptics.swift
// Lightweight tactile feedback for the core logging loop.

import UIKit

enum Haptics {
    /// A confirming tap — bag added, milk logged.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A cautionary tap — discard, delete, or a blocked save.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A soft tick for light, frequent interactions.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
