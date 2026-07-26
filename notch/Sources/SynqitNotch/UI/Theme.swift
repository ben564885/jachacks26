import SwiftUI

/// The notch panel paints a solid black background behind our content and masks it to the
/// notch shape, so everything here is designed as light-on-black. Values live in one place so
/// the expanded view and the compact accessories stay visually consistent.
enum Theme {
    /// Fixed because DynamicNotchKit calls `.fixedSize()` on the expanded content — the view
    /// must state its own width rather than inherit one.
    static let contentWidth: CGFloat = 520

    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 18

    static let affirmative = Color(red: 0.22, green: 0.78, blue: 0.42)
    static let negative = Color(red: 0.95, green: 0.33, blue: 0.31)
    static let instruct = Color(red: 0.42, green: 0.60, blue: 1.0)
    static let neutral = Color(white: 0.62)

    static let primaryText = Color(white: 0.97)
    static let secondaryText = Color(white: 0.68)
    static let tertiaryText = Color(white: 0.46)
    static let hairline = Color(white: 1.0, opacity: 0.10)
    static let surface = Color(white: 1.0, opacity: 0.07)

    static let corner: CGFloat = 10

    /// Matches the library's own opening feel so our internal transitions don't fight the
    /// notch expansion.
    static let stateChange: Animation = .smooth(duration: 0.28)

    static func accentColor(_ accent: OptionAccent) -> Color {
        switch accent {
        case .affirmative: affirmative
        case .negative: negative
        case .instruct: instruct
        case .neutral: neutral
        }
    }
}

/// A pill button sized and coloured for the notch surface.
struct NotchButtonStyle: ButtonStyle {
    var accent: Color
    var isProminent: Bool = true
    /// Whether the button should stretch to share the row. Secondary actions size to their
    /// label instead — letting them stretch starves them of width and wraps the title one
    /// character per line.
    var fill: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isProminent ? Color.black.opacity(0.88) : accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: fill ? .infinity : nil)
            .background {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(isProminent ? accent : accent.opacity(0.16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(accent.opacity(isProminent ? 0 : 0.35), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Small borderless control used for secondary affordances (cancel, dismiss).
struct NotchQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface.opacity(configuration.isPressed ? 1.6 : 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
