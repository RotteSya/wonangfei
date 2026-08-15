import SwiftUI
import UIKit

enum WNFTheme {
    // MARK: - Palette
    // Every token is a dynamic color: the light column is the original brand
    // palette (unchanged), the dark column is the warm "熄灯的工位" scheme —
    // never neutral gray, always warm brown-black so the yellow keeps glowing.

    /// Page background. 奶油白 / 熄灯暖黑。
    static let bg = dynamic(0xFFF6E5, 0x16120E)
    /// Warmer accent wash. 淡黄 / 深一档的暖黑。
    static let bgWarm = dynamic(0xFCEAB7, 0x201A12)
    /// Soft tinted surface (chips, inset panels).
    static let surfaceSoft = dynamic(0xFFF1D2, 0x282118)
    /// Elevated card surface. 白卡 / 暖黑卡。(Was hard-coded Color.white.)
    static let surface = dynamic(0xFFFFFF, 0x251F17)
    /// Primary text & filled pills. 反思黑 / 奶油字。
    static let ink = dynamic(0x0D0D0D, 0xF4ECDD)
    /// The "black card" surface (profile banner, achievement card, tab pill).
    /// Stays dark in dark mode — it is a surface, not text.
    static let inkSurface = dynamic(0x0D0D0D, 0x211B14)
    /// Secondary text.
    static let inkSoft = dynamic(0x3A3530, 0xD5C9B4)
    /// Tertiary text.
    static let muted = dynamic(0x9A938A, 0x8E8372)
    /// Hairline strokes.
    static let hairline = dynamicAlpha(0x000000, 0.08, 0xFFFFFF, 0.10)
    /// Progress-bar trough. Original tan in light; recessed warm black in dark.
    static let track = dynamic(0xF2E6BF, 0x2A2318)

    /// 窝囊黄 — identical in both schemes; it is the brand anchor.
    static let yellow = Color(red: 1.0, green: 0.7843, blue: 0.2392)
    static let gold = Color(red: 1.0, green: 0.8235, blue: 0.3020)
    static let cyan = Color(red: 0.0, green: 0.8980, blue: 1.0)
    static let cyanSoft = dynamic(0xB6F5FB, 0x0E2C32)
    static let coral = Color(red: 1.0, green: 0.3608, blue: 0.3412)
    static let coralSoft = dynamic(0xFFD7D2, 0x3D1915)

    // MARK: - Scheme-independent constants
    // 凭证永远是纸——导出的分享图不跟随深色模式，纸就是纸。
    static let paper = Color.white
    /// 反思黑 as a constant — for marks that must stay black in both schemes
    /// (progress-knob ring, voucher ink, chips sitting on the brand yellow).
    static let inkFixed = Color(red: 0.0510, green: 0.0510, blue: 0.0510)

    // MARK: - Fonts
    /// 站酷庆科黄油体 — display headers only.
    static func display(_ size: CGFloat) -> Font {
        .custom("ZCOOLQingKeHuangYou-Regular", size: size)
    }

    /// JetBrains Mono — every number that wants a "工资条" feel.
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Bold", size: size)
    }

    // MARK: - Helpers
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    private static func dynamicAlpha(_ light: UInt32, _ lightAlpha: CGFloat, _ dark: UInt32, _ darkAlpha: CGFloat) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark).withAlphaComponent(darkAlpha)
                : UIColor(hex: light).withAlphaComponent(lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
