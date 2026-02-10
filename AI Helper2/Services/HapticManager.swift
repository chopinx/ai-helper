import UIKit

/// Centralized haptic feedback for chat interactions
enum HapticManager {
    /// Light tap when sending a message
    static func send() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Soft notification when receiving a response
    static func receive() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error haptic when a message fails
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
