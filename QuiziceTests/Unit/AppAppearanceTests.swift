import UIKit
import XCTest
@testable import Quizice

@MainActor
final class AppAppearanceTests: XCTestCase {
    override func tearDown() {
        SnapshotSupport.tearDown()
        super.tearDown()
    }

    func testThemeSymbolsFallBackWhenUnavailableOnTheCurrentOS() throws {
        for symbol in ["quizice.nonexistent.theme.symbol", "", " \n "] {
            let resolved = ThemeVisualCatalog.resolvedSymbolName(symbol)
            XCTAssertEqual(resolved, QuizTheme.defaultSFSymbolName)
            XCTAssertNotNil(UIImage(systemName: resolved))
            let image = try XCTUnwrap(ThemeVisualCatalog.logoImage(sfSymbolName: symbol))
            XCTAssertEqual(image.renderingMode, .alwaysTemplate)
        }
    }

    func testThemeSymbolsPreserveAvailableServerMetadata() {
        XCTAssertEqual(ThemeVisualCatalog.resolvedSymbolName("  moon.stars.fill \n"), "moon.stars.fill")
    }

    func testAllDesignStylesResolveExpectedSurfaceFamilies() {
        let clean = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .light)
        let radar = SnapshotSupport.appearance(designStyle: .radar)
        let classic = SnapshotSupport.appearance(designStyle: .classic)

        XCTAssertEqual(clean.designStyle, .clean)
        XCTAssertEqual(clean.resolvedInterfaceStyle, .light)
        XCTAssertEqual(clean.card.cornerRadius, 30)
        XCTAssertEqual(clean.primaryButton.cornerRadius, 24)

        XCTAssertEqual(radar.designStyle, .radar)
        XCTAssertEqual(radar.resolvedInterfaceStyle, .dark)
        XCTAssertEqual(radar.row.cornerRadius, 8)
        XCTAssertEqual(radar.themeCardCornerRadius, 10)

        XCTAssertEqual(classic.designStyle, .classic)
        XCTAssertEqual(classic.resolvedInterfaceStyle, .dark)
        XCTAssertEqual(classic.backgroundStyle, .slate5x5)
    }

    func testCleanSystemModeResolvesFromTraitCollection() {
        let lightAppearance = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .system,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )
        let darkAppearance = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .system,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )

        XCTAssertEqual(lightAppearance.resolvedInterfaceStyle, .unspecified)
        XCTAssertEqual(darkAppearance.resolvedInterfaceStyle, .unspecified)
        XCTAssertFalse(lightAppearance.backgroundColor.isEqual(darkAppearance.backgroundColor))
        XCTAssertFalse(lightAppearance.card.backgroundColor.isEqual(darkAppearance.card.backgroundColor))
        XCTAssertTrue(lightAppearance.accentColor.isEqual(UIColor(named: "themeBlack")))
        XCTAssertTrue(lightAppearance.accentForegroundColor.isEqual(UIColor(named: "themeWhite")))
        XCTAssertTrue(darkAppearance.accentColor.isEqual(UIColor(named: "themeWhite")))
        XCTAssertTrue(darkAppearance.accentForegroundColor.isEqual(UIColor(named: "themeBlack")))
    }

    func testCleanAccentUsesMonochromeContrastPair() {
        let lightAppearance = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .light)
        let darkAppearance = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .dark)

        XCTAssertTrue(lightAppearance.accentColor.isEqual(UIColor(named: "themeBlack")))
        XCTAssertTrue(lightAppearance.accentForegroundColor.isEqual(UIColor(named: "themeWhite")))
        XCTAssertTrue(lightAppearance.primaryButton.backgroundColor.isEqual(lightAppearance.accentColor))
        XCTAssertTrue(lightAppearance.primaryButton.borderColor.isEqual(lightAppearance.accentColor))

        XCTAssertTrue(darkAppearance.accentColor.isEqual(UIColor(named: "themeWhite")))
        XCTAssertTrue(darkAppearance.accentForegroundColor.isEqual(UIColor(named: "themeBlack")))
        XCTAssertTrue(darkAppearance.primaryButton.backgroundColor.isEqual(darkAppearance.accentColor))
        XCTAssertTrue(darkAppearance.primaryButton.borderColor.isEqual(darkAppearance.accentColor))
    }

    func testAIThemeKeyboardStyleFollowsDesignAppearance() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let classic = AppAppearance(
            designStyle: .classic,
            cleanColorSchemePreference: .light,
            traitCollection: lightTraits
        )
        let radar = AppAppearance(
            designStyle: .radar,
            cleanColorSchemePreference: .light,
            traitCollection: lightTraits
        )
        let cleanLight = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .light,
            traitCollection: lightTraits
        )
        let cleanDark = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .dark,
            traitCollection: lightTraits
        )
        let cleanSystem = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .system,
            traitCollection: lightTraits
        )

        let classicKeyboard = AIThemeKeyboardStyle(appearance: classic)
        let radarKeyboard = AIThemeKeyboardStyle(appearance: radar)
        let cleanLightKeyboard = AIThemeKeyboardStyle(appearance: cleanLight)
        let cleanDarkKeyboard = AIThemeKeyboardStyle(appearance: cleanDark)
        let cleanSystemKeyboard = AIThemeKeyboardStyle(appearance: cleanSystem)

        XCTAssertEqual(classicKeyboard.interfaceStyle, .dark)
        XCTAssertEqual(radarKeyboard.interfaceStyle, .dark)
        XCTAssertEqual(cleanLightKeyboard.interfaceStyle, .light)
        XCTAssertEqual(cleanDarkKeyboard.interfaceStyle, .dark)
        XCTAssertEqual(cleanSystemKeyboard.interfaceStyle, .unspecified)
        XCTAssertTrue(radarKeyboard.doneButtonTintColor.isEqual(radar.accentColor))
        XCTAssertTrue(
            classicKeyboard.doneButtonTintColor.isEqual(AppAssetColor.fallbackBlue.uiColor)
        )
        XCTAssertTrue(cleanLightKeyboard.doneButtonTintColor.isEqual(cleanLight.accentColor))
        XCTAssertTrue(cleanDarkKeyboard.doneButtonTintColor.isEqual(cleanDark.accentColor))
        XCTAssertTrue(cleanSystemKeyboard.doneButtonTintColor.isEqual(cleanSystem.accentColor))
    }

    func testQuizAlertActionTextContrastsCleanButtonSurfaces() {
        for colorScheme in [CleanColorSchemePreference.light, .dark] {
            let appearance = SnapshotSupport.appearance(
                designStyle: .clean,
                cleanColorScheme: colorScheme
            )

            XCTAssertTrue(
                QuizAlertAction.Emphasis.primary.textColor(in: appearance)
                    .isEqual(appearance.accentForegroundColor)
            )
            XCTAssertFalse(
                QuizAlertAction.Emphasis.primary.textColor(in: appearance)
                    .isEqual(appearance.primaryButton.backgroundColor)
            )
            XCTAssertTrue(
                QuizAlertAction.Emphasis.secondary.textColor(in: appearance)
                    .isEqual(appearance.accentColor)
            )
        }
    }

    func testQuizAlertDestructiveActionUsesReadableThemeAwareStyle() {
        for designStyle in AppDesignStyle.allCases where designStyle.isSelectable {
            let appearance = SnapshotSupport.appearance(
                designStyle: designStyle,
                cleanColorScheme: .light
            )
            let emphasis = QuizAlertAction.Emphasis.destructive
            let style = emphasis.surfaceStyle(in: appearance)

            XCTAssertTrue(style.borderColor.isEqual(emphasis.tintColor(in: appearance)))
            if designStyle == .clean {
                XCTAssertTrue(style.backgroundColor.isEqual(emphasis.tintColor(in: appearance)))
                XCTAssertTrue(emphasis.textColor(in: appearance).isEqual(UIColor.black))
            } else {
                XCTAssertTrue(style.backgroundColor.isEqual(appearance.secondaryButton.backgroundColor))
                XCTAssertTrue(emphasis.textColor(in: appearance).isEqual(emphasis.tintColor(in: appearance)))
            }
        }
    }

    func testQuizThemeActionsStayMonochromeWithoutChangingCatalogIdentity() throws {
        let appearance = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .light)
        let darkAppearance = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .dark)
        let musicTint = try XCTUnwrap(ThemeVisualCatalog.color(from: "#FF8252"))

        XCTAssertFalse(musicTint.isEqual(appearance.accentColor))
        XCTAssertTrue(
            QuizThemeAccentStyle.accentColor(themeID: "music", appearance: appearance)
                .isEqual(appearance.accentColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.primaryButtonTextColor(themeID: "music", appearance: appearance)
                .isEqual(appearance.accentForegroundColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.primaryButtonStyle(themeID: "music", appearance: appearance)
                .backgroundColor.isEqual(appearance.accentColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.secondaryButtonTextColor(themeID: "music", appearance: appearance)
                .isEqual(appearance.accentColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.accentColor(themeID: "custom-theme", appearance: appearance)
                .isEqual(appearance.accentColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.primaryButtonTextColor(themeID: "custom-theme", appearance: appearance)
                .isEqual(appearance.accentForegroundColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.accentColor(themeID: "custom-theme", appearance: darkAppearance)
                .isEqual(darkAppearance.accentColor)
        )
        XCTAssertTrue(
            QuizThemeAccentStyle.primaryButtonTextColor(themeID: "custom-theme", appearance: darkAppearance)
                .isEqual(darkAppearance.accentForegroundColor)
        )
    }

    func testThemeCardStylingDiffersByDesignStyle() {
        let baseColor = UIColor.systemBlue
        let clean = SnapshotSupport.appearance(designStyle: .clean)
        let cleanDark = SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .dark)
        let radar = SnapshotSupport.appearance(designStyle: .radar)
        let classic = SnapshotSupport.appearance(designStyle: .classic)

        XCTAssertTrue(clean.themeCardBackground(baseColor: baseColor).isEqual(clean.card.backgroundColor))
        XCTAssertTrue(clean.themeCardTextColor(baseColor: baseColor).isEqual(clean.surfaceTextColor))
        XCTAssertEqual(clean.themeCardShadow.opacity, 0)
        XCTAssertGreaterThan(cleanDark.themeCardShadow.opacity, 0)
        XCTAssertTrue(radar.themeCardTextColor(baseColor: baseColor).isEqual(radar.accentColor))
        XCTAssertFalse(classic.themeCardBackground(baseColor: baseColor).isEqual(baseColor))
    }

    func testApplySurfaceAndActionAppearanceMutatesUIKitControls() {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        let view = UIView()
        let button = UIButton(type: .system)

        view.applySurfaceStyle(appearance.card)
        button.applyActionAppearance(
            appearance.primaryButton,
            appearance: appearance,
            textColor: appearance.accentForegroundColor
        )

        XCTAssertTrue(view.backgroundColor?.isEqual(appearance.card.backgroundColor) ?? false)
        XCTAssertEqual(view.layer.cornerRadius, appearance.card.cornerRadius)
        XCTAssertEqual(view.layer.borderWidth, appearance.card.borderWidth)
        XCTAssertTrue(button.backgroundColor?.isEqual(appearance.primaryButton.backgroundColor) ?? false)
        XCTAssertTrue(button.titleColor(for: .normal)?.isEqual(appearance.accentForegroundColor) ?? false)
        XCTAssertTrue(button.titleColor(for: .disabled)?.isEqual(appearance.disabledTextColor) ?? false)
    }

    func testApplyingBackgroundInstallsAndReusesMeshHost() throws {
        let view = UIView()
        let original = AppAppearance(
            designStyle: .classic,
            cleanColorSchemePreference: .dark,
            backgroundStyle: .legacySlate,
            traitCollection: .init(userInterfaceStyle: .dark)
        )
        let denserMesh = AppAppearance(
            designStyle: .classic,
            cleanColorSchemePreference: .dark,
            backgroundStyle: .slate4x4,
            traitCollection: .init(userInterfaceStyle: .dark)
        )

        original.applyBackground(to: view)
        let installedBackground = try XCTUnwrap(
            view.subviews.first(where: { $0.accessibilityIdentifier == "appBackgroundView" })
        )

        denserMesh.applyBackground(to: view)

        XCTAssertTrue(installedBackground === view.subviews.first)
        XCTAssertEqual(view.subviews.filter { $0.accessibilityIdentifier == "appBackgroundView" }.count, 1)
    }

    func testEdgeAwareMeshMovesVisibleBoundariesWithoutChangingStandardMotion() {
        let basePoints = (0..<5).flatMap { row in
            (0..<5).map { column in
                SIMD2<Float>(Float(column) / 4, Float(row) / 4)
            }
        }
        let sampleDate = Date(timeIntervalSinceReferenceDate: 1)
        let standardPoints = AppMeshGradientMotion.animatedPoints(
            at: sampleDate,
            width: 5,
            height: 5,
            basePoints: basePoints,
            cycleDuration: 4,
            horizontalAmplitude: 0.050,
            verticalAmplitude: 0.035,
            edgeAmplitude: 0.070,
            profile: .standard
        )
        let edgeAwarePoints = AppMeshGradientMotion.animatedPoints(
            at: sampleDate,
            width: 5,
            height: 5,
            basePoints: basePoints,
            cycleDuration: 4,
            horizontalAmplitude: 0.050,
            verticalAmplitude: 0.035,
            edgeAmplitude: 0.070,
            profile: .edgeAware
        )
        let repeatedPoints = AppMeshGradientMotion.animatedPoints(
            at: Date(timeIntervalSinceReferenceDate: 5),
            width: 5,
            height: 5,
            basePoints: basePoints,
            cycleDuration: 4,
            horizontalAmplitude: 0.050,
            verticalAmplitude: 0.035,
            edgeAmplitude: 0.070,
            profile: .edgeAware
        )

        XCTAssertEqual(standardPoints[1], basePoints[1])
        XCTAssertEqual(standardPoints[10], basePoints[10])
        XCTAssertNotEqual(edgeAwarePoints[1], basePoints[1])
        XCTAssertNotEqual(edgeAwarePoints[10], basePoints[10])
        XCTAssertEqual(edgeAwarePoints[6], standardPoints[6])
        for cornerIndex in [0, 4, 20, 24] {
            XCTAssertEqual(edgeAwarePoints[cornerIndex], basePoints[cornerIndex])
        }
        for pointIndex in edgeAwarePoints.indices {
            XCTAssertEqual(
                edgeAwarePoints[pointIndex].x,
                repeatedPoints[pointIndex].x,
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                edgeAwarePoints[pointIndex].y,
                repeatedPoints[pointIndex].y,
                accuracy: 0.000_001
            )
        }
    }

    func testBackgroundStylePersistsAndFlowsIntoAppearance() {
        let suiteName = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AppAppearanceStore(userDefaults: defaults, notificationCenter: NotificationCenter())

        store.backgroundStyle = .slate5x5
        let appearance = store.appearance(compatibleWith: .init(userInterfaceStyle: .dark))

        XCTAssertEqual(store.backgroundStyle, .slate5x5)
        XCTAssertEqual(appearance.backgroundStyle, .slate5x5)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStoreIgnoresRepeatedWrites() {
        let suiteName = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let notificationCenter = NotificationCenter()
        let store = AppAppearanceStore(userDefaults: defaults, notificationCenter: notificationCenter)
        var notificationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .appAppearanceDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }

        store.designStyle = .clean
        store.designStyle = .clean

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(store.designStyle, .clean)
        notificationCenter.removeObserver(observer)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
