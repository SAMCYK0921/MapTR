//
//  Haptics.swift
//  MTR Lift Guide
//
//  Centralised haptic feedback so every tap / pop / success feels the same.
//

import UIKit

enum Haptics {

    /// Light tap for ordinary button presses.
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Configurable impact, e.g. `.rigid` for a bubble pop, `.medium` for advance.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Subtle tick for selection changes (tab switches, pickers).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Positive confirmation (request posted, help completed).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
