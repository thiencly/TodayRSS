//
//  HapticManager.swift
//  VibeRSS_Test
//
//  Purpose: Provides haptic feedback throughout the app
//

import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private var lastTypingHaptic: Date = .distantPast
    private let typingHapticInterval: TimeInterval = 0.04 // 40ms between haptics

    private init() {
        // Prepare generators for lower latency
        lightImpact.prepare()
        softImpact.prepare()
        selectionFeedback.prepare()
    }

    /// Typing haptic for streaming text - throttled to avoid excessive vibration
    func typingHaptic() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingHaptic) >= typingHapticInterval else { return }
        lastTypingHaptic = now

        DispatchQueue.main.async { [weak self] in
            self?.softImpact.impactOccurred(intensity: 0.4)
        }
    }

    /// Light tap feedback for button presses
    func lightTap() {
        DispatchQueue.main.async { [weak self] in
            self?.lightImpact.impactOccurred(intensity: 0.5)
        }
    }

    /// Selection changed feedback
    func selection() {
        DispatchQueue.main.async { [weak self] in
            self?.selectionFeedback.selectionChanged()
        }
    }

    /// Success feedback
    func success() {
        DispatchQueue.main.async { [weak self] in
            self?.notificationFeedback.notificationOccurred(.success)
        }
    }

    /// Error feedback
    func error() {
        DispatchQueue.main.async { [weak self] in
            self?.notificationFeedback.notificationOccurred(.error)
        }
    }

    /// Warning feedback
    func warning() {
        DispatchQueue.main.async { [weak self] in
            self?.notificationFeedback.notificationOccurred(.warning)
        }
    }

    /// Prepare generators (call before expected haptic use)
    func prepare() {
        lightImpact.prepare()
        softImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }
}
