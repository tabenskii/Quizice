import CoreGraphics

/// Layout follows the space available to the current scene, including resized iPad windows.
struct AppAdaptiveLayout: Equatable {
    let width: CGFloat
    let accessibility: Bool

    init(width: CGFloat, accessibility: Bool = false) {
        self.width = max(0, width)
        self.accessibility = accessibility
    }

    var isCompact: Bool { width < 600 }
    var homeContainerWidth: CGFloat { min(width, 1_180) }
    var preferredThemeColumns: Int { accessibility ? 1 : (isCompact ? 2 : (width < 900 ? 3 : 4)) }
    var expandedCardMaximumWidth: CGFloat { isCompact ? 430 : 560 }
    var resultMaximumWidth: CGFloat { expandedCardMaximumWidth }
    var questionMaximumWidth: CGFloat { isCompact ? 430 : 640 }
    var actionMaximumWidth: CGFloat { isCompact ? width : 640 }
}
