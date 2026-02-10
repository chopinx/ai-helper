import SwiftUI

// MARK: - Design System

/// Centralized design tokens for AI Helper2.
/// Consolidates colors, typography, spacing, and reusable styles used across views.
enum DS {

    // MARK: - Colors

    enum Colors {
        /// Primary action color (buttons, links, user bubbles)
        static let accent = Color.blue
        /// Success states, reminders, completion
        static let success = Color.green
        /// Errors, destructive actions
        static let error = Color.red
        /// Warnings, network issues
        static let warning = Color.orange

        /// AI message bubble background
        static let aiBubble = Color(.systemGray5)
        /// Card and surface background
        static let surface = Color(.systemBackground)
        /// Grouped/recessed background
        static let groupedBackground = Color(.systemGray6)
        /// Subtle border for cards
        static let border = Color(.systemGray4)

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
        static let bubble: CGFloat = 16
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
