import UIKit

// MARK: - Haptic Manager

final class HapticManager {
    static let shared = HapticManager()

    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        // Prepare generators for faster response
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    // MARK: - Notification Feedback

    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    // MARK: - Selection Feedback

    func selection() {
        selectionGenerator.selectionChanged()
    }

    // MARK: - Impact Feedback

    func lightImpact() {
        lightImpactGenerator.impactOccurred()
    }

    func mediumImpact() {
        mediumImpactGenerator.impactOccurred()
    }

    func heavyImpact() {
        heavyImpactGenerator.impactOccurred()
    }

    func impact(intensity: CGFloat) {
        mediumImpactGenerator.impactOccurred(intensity: intensity)
    }
}

// MARK: - View Extension

import SwiftUI

extension View {
    func onTapWithHaptic(_ action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticManager.shared.selection()
            action()
        }
    }

    func onTapWithSuccessHaptic(_ action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticManager.shared.success()
            action()
        }
    }
}
