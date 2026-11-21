import UIKit

enum ThemeIconVisualStyle {
    static let shadowOffset: CGFloat = 3
    static let shadowAlpha: CGFloat = 0.26
}

enum AIThemeVisualStyle {
    static let gradientStartColor = AppAssetColor.aiGradientStart.uiColor
    static let gradientEndColor = AppAssetColor.aiGradientEnd.uiColor
    static let accentColor = AppAssetColor.aiAccent.uiColor

    static let gradientColors = [gradientStartColor, gradientEndColor]
}

enum ThemeVisualCatalog {
    static func resolvedSymbolName(_ sfSymbolName: String) -> String {
        let normalizedName = sfSymbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return UIImage(systemName: normalizedName) == nil
            ? QuizTheme.defaultSFSymbolName
            : normalizedName
    }

    static func logoImage(sfSymbolName: String) -> UIImage? {
        UIImage(systemName: resolvedSymbolName(sfSymbolName))?
            .withRenderingMode(.alwaysTemplate)
    }

    static func tintColor(for theme: QuizTheme) -> UIColor {
        tintColor(colorHex: theme.colorHex, themeID: theme.stableID)
    }

    static func tintColor(for theme: OnboardingTheme) -> UIColor {
        tintColor(colorHex: theme.colorHex, themeID: theme.id)
    }

    static func tintColor(colorHex: String?, themeID: String) -> UIColor {
        color(from: colorHex) ?? fallbackTintColors[paletteIndex(for: themeID)]
    }

    static func color(from colorHex: String?) -> UIColor? {
        guard
            let normalized = QuizThemeColor.normalizedHex(colorHex),
            let value = UInt32(normalized.dropFirst(), radix: 16)
        else { return nil }
        return UIColor(hex: value)
    }

    private static let fallbackTintColors = [
        AppAssetColor.fallbackIndigo.uiColor,
        AppAssetColor.fallbackTeal.uiColor,
        AppAssetColor.fallbackOrange.uiColor,
        AppAssetColor.fallbackPink.uiColor,
        AppAssetColor.fallbackGreen.uiColor,
        AppAssetColor.fallbackPurple.uiColor,
        AppAssetColor.fallbackBlue.uiColor,
        AppAssetColor.fallbackRed.uiColor
    ]

    private static func paletteIndex(for themeID: String) -> Int {
        let hash = themeID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(fallbackTintColors.count))
    }
}
