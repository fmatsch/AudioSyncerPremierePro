import SwiftUI

enum PPTheme {
    static let bgDark = Color(red: 0.118, green: 0.118, blue: 0.118)       // #1E1E1E
    static let bgPanel = Color(red: 0.176, green: 0.176, blue: 0.176)      // #2D2D2D
    static let bgInput = Color(red: 0.137, green: 0.137, blue: 0.137)      // #232323
    static let accent = Color(red: 0.620, green: 0.620, blue: 1.0)         // #9E9EFF
    static let accentDim = Color(red: 0.400, green: 0.400, blue: 0.800)
    static let textPrimary = Color(red: 0.878, green: 0.878, blue: 0.878)  // #E0E0E0
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.600)
    static let border = Color(red: 0.250, green: 0.250, blue: 0.250)
    static let success = Color(red: 0.400, green: 0.800, blue: 0.400)
    static let error = Color(red: 0.900, green: 0.350, blue: 0.350)
    static let warning = Color(red: 0.900, green: 0.700, blue: 0.200)
    static let audioMaster = Color(red: 0.200, green: 0.600, blue: 0.900)
    static let camera = Color(red: 0.900, green: 0.500, blue: 0.200)

    static let cornerRadius: CGFloat = 6
    static let panelPadding: CGFloat = 12
    static let spacing: CGFloat = 8
}

struct PPButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isPrimary ? .white : PPTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                    .fill(isPrimary ? PPTheme.accent : PPTheme.bgInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                    .stroke(isPrimary ? Color.clear : PPTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct PPPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                    .fill(PPTheme.bgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                    .stroke(PPTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func ppPanel() -> some View {
        modifier(PPPanelModifier())
    }
}
