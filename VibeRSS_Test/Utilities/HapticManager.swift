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
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    // Thread-safe timing for typing haptics
    private let hapticLock = NSLock()
    private var lastTypingHapticTime: CFAbsoluteTime = 0
    private let typingHapticInterval: CFAbsoluteTime = 0.12 // 120ms between haptics (~8hz, well under 32hz limit)

    private init() {
        // Prepare generators for lower latency
        lightImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        selectionFeedback.prepare()
    }

    /// Typing haptic for streaming text - throttled to avoid excessive vibration
    func typingHaptic() {
        let now = CFAbsoluteTimeGetCurrent()

        // Thread-safe check and update
        hapticLock.lock()
        let elapsed = now - lastTypingHapticTime
        guard elapsed >= typingHapticInterval else {
            hapticLock.unlock()
            return
        }
        lastTypingHapticTime = now
        hapticLock.unlock()

        // Fire haptic on main thread
        DispatchQueue.main.async { [weak self] in
            self?.softImpact.impactOccurred(intensity: 0.4)
        }
    }

    /// Sharp tap feedback for button presses
    func lightTap() {
        DispatchQueue.main.async { [weak self] in
            self?.rigidImpact.impactOccurred(intensity: 0.8)
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
