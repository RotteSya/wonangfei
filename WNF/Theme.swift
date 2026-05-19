import SwiftUI

enum WNFTheme {
    @MainActor static var bg: Color { PremiumThemeRuntime.palette.bg }
    @MainActor static var bgWarm: Color { PremiumThemeRuntime.palette.bgWarm }
    @MainActor static var surfaceSoft: Color { PremiumThemeRuntime.palette.surfaceSoft }
    @MainActor static var yellow: Color { PremiumThemeRuntime.palette.yellow }
    @MainActor static var gold: Color { PremiumThemeRuntime.palette.gold }
    @MainActor static var ink: Color { PremiumThemeRuntime.palette.ink }
    @MainActor static var inkSoft: Color { PremiumThemeRuntime.palette.inkSoft }
    @MainActor static var muted: Color { PremiumThemeRuntime.palette.muted }
    @MainActor static var cyan: Color { PremiumThemeRuntime.palette.cyan }
    @MainActor static var cyanSoft: Color { PremiumThemeRuntime.palette.cyanSoft }
    @MainActor static var coral: Color { PremiumThemeRuntime.palette.coral }
    @MainActor static var coralSoft: Color { PremiumThemeRuntime.palette.coralSoft }
    static let hairline = Color.black.opacity(0.08)

    static let display = Font.custom("ZCOOLQingKeHuangYou-Regular", size: 20)
    static let body = Font.custom("Nunito", size: 15)
    static let mono = Font.custom("JetBrainsMono-Regular", size: 15)
}
