import SwiftUI

enum AppTheme {
    static let pageBackground = Color(hex: 0x0D0D0D)
    static let panelBackground = Color.black
    static let accent = Color(hex: 0xC8FF00)
    static let destructive = Color(hex: 0xFF453A)
    static let secondary = Color(hex: 0x8E8E93)

    static let topSpacerHeight: CGFloat = 64
    static let idlePanelHeight: CGFloat = 116
    static let recordingPanelHeight: CGFloat = 236
    static let panelCornerRadius: CGFloat = 28
    static let buttonCornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 24
    static let primaryButtonHeight: CGFloat = 72
    static let minimumTapSize: CGFloat = 44
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
