import SwiftUI

enum Theme {
    // MARK: - Colors

    static let background = Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
    static let secondaryBackground = Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0))
    static let tertiaryBackground = Color(nsColor: NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0))

    static let accent = Color.blue
    static let accentGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let text = Color.white
    static let secondaryText = Color.gray
    static let tertiaryText = Color(white: 0.5)

    static let success = Color.green
    static let warning = Color.yellow
    static let error = Color.red
    static let info = Color.blue

    static let border = Color.white.opacity(0.1)
    static let divider = Color.white.opacity(0.05)

    // MARK: - Terminal Colors (dynamic based on Appearance settings)

    static let terminalBackground = Color.black

    static var terminalText: Color {
        switch UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "default" {
        case "amber": return Color.orange
        case "white": return Color.white
        case "cyan": return Color.cyan
        default: return Color.green
        }
    }

    static var terminalCommand: Color {
        switch UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "default" {
        case "amber": return Color.yellow
        case "white": return Color(white: 0.85)
        case "cyan": return Color.blue
        default: return Color.cyan
        }
    }

    static let terminalError = Color.red
    static let terminalSystem = Color.yellow

    // MARK: - AI Colors

    static let aiUser = Color.purple
    static let aiResponse = Color(nsColor: NSColor(red: 0.72, green: 0.55, blue: 1.0, alpha: 1.0))
    static let aiBadge = Color.purple

    // MARK: - Terminal Font Size

    static var terminalFontSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "terminalFontSize")
        return stored > 0 ? stored : 14.0
    }

    // MARK: - Gradients

    static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.05),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let healthyGradient = LinearGradient(
        colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warningGradient = LinearGradient(
        colors: [Color.yellow.opacity(0.3), Color.yellow.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let criticalGradient = LinearGradient(
        colors: [Color.red.opacity(0.3), Color.red.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Spacing

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 12
    static let paddingLarge: CGFloat = 16
    static let paddingXLarge: CGFloat = 24

    // MARK: - Corner Radius

    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 10
    static let cornerRadiusLarge: CGFloat = 14

    // MARK: - Sidebar

    static let sidebarWidth: CGFloat = 220

    // MARK: - Animation

    static let animationFast: Animation = .easeInOut(duration: 0.15)
    static let animationMedium: Animation = .easeInOut(duration: 0.25)
    static let animationSlow: Animation = .easeInOut(duration: 0.4)

    // MARK: - Shadows

    static let shadowSmall = Color.black.opacity(0.2)
    static let shadowMedium = Color.black.opacity(0.3)
    static let shadowLarge = Color.black.opacity(0.4)
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .background(Theme.cardGradient)
            .background(Theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    func terminalStyle() -> some View {
        self
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Theme.terminalText)
            .background(Theme.terminalBackground)
    }

    func statusColor(_ status: HealthStatus) -> some View {
        switch status {
        case .healthy:
            return self.foregroundStyle(Theme.success)
        case .warning:
            return self.foregroundStyle(Theme.warning)
        case .critical:
            return self.foregroundStyle(Theme.error)
        case .unknown:
            return self.foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Custom Modifiers

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func glow(_ color: Color = .blue, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}
