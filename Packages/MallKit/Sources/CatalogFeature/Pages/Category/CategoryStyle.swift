import SwiftUI

/// Visual tokens resolved from the fixed Android reference
/// (`CategoryScreen.kt` + `AppTheme`/`Color`/`Type`/`Size`/`Shape` at cf5029b).
/// The reference page uses MaterialTheme roles, not the home page's custom
/// card treatment; these are the exact light/dark values recorded for the
/// category surface groups, text roles and radius/spacing leaves.
struct CategoryPalette {
    let background: Color
    let surface: Color
    let primary: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let tertiary: Color

    static func resolve(_ scheme: ColorScheme) -> CategoryPalette {
        if scheme == .dark {
            return CategoryPalette(
                background: rgb(0x11_11_11),
                surface: rgb(0x1B_1B_1B),
                primary: rgb(0x46_5C_FF),
                onSurface: rgb(0xD1_D1_D1),
                // Material3 baseline role: the reference theme does not override it.
                onSurfaceVariant: rgb(0xCA_C4_D0),
                tertiary: rgb(0x8D_8D_8D)
            )
        }
        return CategoryPalette(
            background: rgb(0xF1_F4_FA),
            surface: rgb(0xFF_FF_FF),
            primary: rgb(0x46_5C_FF),
            onSurface: rgb(0x18_18_18),
            onSurfaceVariant: rgb(0x49_45_4F),
            tertiary: rgb(0xB2_B2_B2)
        )
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Fixed reference measurements in points (Android dp is used 1:1, the design
/// tokens themselves are the dp conversion of the original px specification).
enum CategoryMetrics {
    static let leftColumnWidth: CGFloat = 100
    static let rootRowMinHeight: CGFloat = 50
    static let indicatorWidth: CGFloat = 3
    static let indicatorHeight: CGFloat = 24
    static let groupCornerRadius: CGFloat = 16

    static let rightHorizontalPadding: CGFloat = 8
    static let rightTopPadding: CGFloat = 16
    static let groupSpacing: CGFloat = 24
    static let groupBottomPadding: CGFloat = 8
    static let titleToGridSpacing: CGFloat = 8

    static let titleLineWidth: CGFloat = 4
    static let titleLineHeight: CGFloat = 20
    static let titleLineCornerRadius: CGFloat = 2
    static let titleSpacing: CGFloat = 8

    static let gridColumnCount = 3
    static let subItemPadding: CGFloat = 8
    static let subImageCornerRadius: CGFloat = 12
    static let subNameTopSpacing: CGFloat = 4

    static let stateIconArea: CGFloat = 120
    static let stateIconPointSize: CGFloat = 96
    static let stateTitleSpacing: CGFloat = 24
    static let stateSubtitleSpacing: CGFloat = 8
    static let stateRetrySpacing: CGFloat = 24
    static let retryBorderWidth: CGFloat = 0.5
    static let retryHorizontalPadding: CGFloat = 50
    static let retryMaxWidth: CGFloat = 200
    static let statePadding: CGFloat = 16

    static let bottomPaddingFloor: CGFloat = 16
    static let bottomPaddingReserve: CGFloat = 80
}
