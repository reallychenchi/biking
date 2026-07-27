import SwiftUI
import UIKit

enum AppTheme {
    static let pageBackground = Color("AppPageBackground")
    static let panelBackground = Color("AppPanelBackground")
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let accentForeground = Color("AppAccentForeground")
    static let primaryActionBackground = Color(hex: 0xC8FF00)
    static let primaryActionForeground = Color.black
    static let destructive = Color(uiColor: .systemRed)
    static let destructiveForeground = Color.white
    static let separator = Color(uiColor: .separator)

    static let idlePanelHeight: CGFloat = 116
    static let recordingPanelHeight: CGFloat = 236
    static let panelCornerRadius: CGFloat = 28
    static let buttonCornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 24
    static let primaryButtonHeight: CGFloat = 72
    static let minimumTapSize: CGFloat = 44
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearancePreference"

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum AppAppearance: String, Hashable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            self = .light
        case .dark:
            self = .dark
        @unknown default:
            assertionFailure("Unhandled color scheme")
            self = .light
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        }
    }
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
