import XCTest
@testable import Quizice

final class AppAdaptiveLayoutTests: XCTestCase {
    func testColumnBreakpointsFollowAvailableWindowWidth() {
        for (width, columns) in [(390, 2), (599, 2), (600, 3), (899, 3), (900, 4), (1_366, 4)] {
            XCTAssertEqual(AppAdaptiveLayout(width: CGFloat(width)).preferredThemeColumns, columns)
        }
    }

    func testAccessibilityAlwaysUsesOneColumn() {
        for width in [390, 600, 900, 1_366] {
            XCTAssertEqual(AppAdaptiveLayout(width: CGFloat(width), accessibility: true).preferredThemeColumns, 1)
        }
    }

    func testResizingToCompactRestoresPhoneContentWidths() {
        let wide = AppAdaptiveLayout(width: 1_366)
        XCTAssertEqual(wide.homeContainerWidth, 1_180)
        XCTAssertEqual(wide.expandedCardMaximumWidth, 560)
        XCTAssertEqual(wide.resultMaximumWidth, 560)
        XCTAssertEqual(wide.questionMaximumWidth, 640)
        XCTAssertEqual(wide.actionMaximumWidth, 640)

        let compact = AppAdaptiveLayout(width: 500)
        XCTAssertTrue(compact.isCompact)
        XCTAssertEqual(compact.homeContainerWidth, 500)
        XCTAssertEqual(compact.expandedCardMaximumWidth, 430)
        XCTAssertEqual(compact.resultMaximumWidth, 430)
        XCTAssertEqual(compact.questionMaximumWidth, 430)
        XCTAssertEqual(compact.actionMaximumWidth, 500)
    }
}
