import SwiftUI
import UIKit

// MARK: - Design System

/// Centralized design tokens for AI Helper2.
/// Consolidates colors, typography, spacing, and reusable styles used across views.
enum DS {

    // MARK: - Colors

    enum Colors {
        /// Primary action color (buttons, links, highlights)
        static let accent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.40, green: 0.61, blue: 1.0, alpha: 1)   // soft blue
                : UIColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1)  // vibrant blue
        })
        /// Success states, reminders, completion
        static let success = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.30, green: 0.82, blue: 0.50, alpha: 1)
                : UIColor(red: 0.20, green: 0.72, blue: 0.40, alpha: 1)
        })
        /// Errors, destructive actions
        static let error = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)
                : UIColor(red: 0.92, green: 0.26, blue: 0.26, alpha: 1)
        })
        /// Warnings, network issues
        static let warning = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1)
                : UIColor(red: 0.95, green: 0.60, blue: 0.10, alpha: 1)
        })

        // MARK: Chat Colors

        /// User message bubble background
        static let userBubble = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.42, blue: 0.82, alpha: 1)  // deep blue
                : UIColor(red: 0.22, green: 0.50, blue: 0.96, alpha: 1)  // bright blue
        })
        /// AI message bubble background
        static let aiBubble = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)  // dark surface
                : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)    // white
        })
        /// Chat area background
        static let chatBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)  // near-black
                : UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)  // soft gray
        })
        /// Send button accent
        static let sendButton = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.40, green: 0.61, blue: 1.0, alpha: 1)
                : UIColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1)
        })
        /// Timestamp separator text
        static let timestampText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.45)
                : UIColor(white: 0.0, alpha: 0.45)
        })
        /// User bubble foreground text
        static let userBubbleText = Color.white
        /// AI bubble foreground text
        static let aiBubbleText = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.93, alpha: 1)
                : UIColor(white: 0.07, alpha: 1)
        })

        // MARK: Chat Input

        /// Input area background
        static let inputBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        })
        /// Input field background
        static let inputField = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
                : UIColor(white: 1.0, alpha: 1)
        })
        /// Input area top border
        static let inputBorder = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 0.0, alpha: 0.08)
        })

        // MARK: Avatars

        /// User avatar background
        static let avatarUser = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.42, blue: 0.82, alpha: 0.25)
                : UIColor(red: 0.22, green: 0.50, blue: 0.96, alpha: 0.12)
        })
        /// User avatar icon
        static let avatarUserIcon = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.50, green: 0.70, blue: 1.0, alpha: 1)
                : UIColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1)
        })
        /// AI avatar background
        static let avatarAI = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 0.25)
                : UIColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 0.12)
        })
        /// AI avatar icon
        static let avatarAIIcon = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.55, blue: 1.0, alpha: 1)
                : UIColor(red: 0.50, green: 0.30, blue: 0.82, alpha: 1)
        })

        // MARK: Surfaces

        /// Card and surface background
        static let surface = Color(.systemBackground)
        /// Grouped/recessed background
        static let groupedBackground = Color(.systemGray6)
        /// Subtle border for cards
        static let border = Color(.systemGray4)
        /// Code block background
        static let codeBg = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
                : UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        })

        /// Tinted backgrounds for banners/alerts
        static func tint(_ color: Color, opacity: Double = 0.1) -> Color {
            color.opacity(opacity)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let avatarSize: CGFloat = 40
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        /// Small elements: badges, tags
        static let small: CGFloat = 6
        /// Medium elements: cards, code blocks, input fields
        static let medium: CGFloat = 10
        /// Large elements: buttons, sheets, message bubbles
        static let large: CGFloat = 14
        /// Chat bubbles
        static let bubble: CGFloat = 14
    }

}

// MARK: - Typography Modifiers

struct HeadingModifier: ViewModifier {
    enum Size { case large, medium }
    let size: Size

    func body(content: Content) -> some View {
        switch size {
        case .large:
            content.font(.title).fontWeight(.bold)
        case .medium:
            content.font(.title2).fontWeight(.semibold)
        }
    }
}

extension View {
    func heading(_ size: HeadingModifier.Size = .medium) -> some View {
        modifier(HeadingModifier(size: size))
    }
}

// MARK: - Button Styles

/// Full-width primary button used in onboarding and action sheets.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = DS.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(DS.CornerRadius.large)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Small pill button for inline actions (e.g., "Allow", "Settings" in banners).
struct PillButtonStyle: ButtonStyle {
    var color: Color = DS.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(color)
            .cornerRadius(DS.CornerRadius.small + 2)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Secondary button: outlined with accent border, no fill.
/// Used for cancel/dismiss actions (e.g., PendingActionsSheet cancel).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Colors.groupedBackground)
            .foregroundColor(.primary)
            .cornerRadius(DS.CornerRadius.large)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - View Modifiers

/// Standard card styling: surface background, border, rounded corners.
struct CardModifier: ViewModifier {
    var isSelected: Bool = false
    var selectedColor: Color = DS.Colors.accent

    func body(content: Content) -> some View {
        content
            .padding()
            .background(DS.Colors.surface)
            .cornerRadius(DS.CornerRadius.medium + 2)
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium + 2)
                    .stroke(
                        isSelected ? selectedColor : DS.Colors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
    }
}

/// Banner styling for warnings/errors at the top of views.
struct BannerModifier: ViewModifier {
    var tintColor: Color

    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.lg)
            .background(DS.Colors.tint(tintColor))
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium)
                    .stroke(DS.Colors.tint(tintColor, opacity: 0.3), lineWidth: 1)
            )
            .cornerRadius(DS.CornerRadius.medium)
    }
}

extension View {
    func cardStyle(isSelected: Bool = false, selectedColor: Color = DS.Colors.accent) -> some View {
        modifier(CardModifier(isSelected: isSelected, selectedColor: selectedColor))
    }

    func bannerStyle(tintColor: Color) -> some View {
        modifier(BannerModifier(tintColor: tintColor))
    }
}
