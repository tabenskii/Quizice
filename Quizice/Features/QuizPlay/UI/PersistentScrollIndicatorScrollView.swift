import UIKit

/// Keeps the scroll position visible even while the reader is not dragging.
final class PersistentScrollIndicatorScrollView: UIScrollView {
    static let indicatorGutter: CGFloat = 10

    private let persistentIndicator = UIView()
    private let indicatorWidth: CGFloat = 3
    private let indicatorInset: CGFloat = 2
    private let minimumIndicatorHeight: CGFloat = 24

    var persistentIndicatorColor: UIColor = .secondaryLabel {
        didSet { persistentIndicator.backgroundColor = persistentIndicatorColor }
    }

    override var contentSize: CGSize {
        didSet {
            if contentSize != oldValue { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureIndicator()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureIndicator()
    }

    private func configureIndicator() {
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        persistentIndicator.accessibilityIdentifier = "persistentScrollIndicator"
        persistentIndicator.isUserInteractionEnabled = false
        persistentIndicator.accessibilityElementsHidden = true
        persistentIndicator.backgroundColor = persistentIndicatorColor
        persistentIndicator.layer.cornerRadius = indicatorWidth / 2
        persistentIndicator.isHidden = true
        addSubview(persistentIndicator)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = adjustedContentInset
        let visibleHeight = bounds.height - insets.top - insets.bottom
        let scrollRange = contentSize.height - visibleHeight
        let trackHeight = visibleHeight - indicatorInset * 2
        guard bounds.width > 0, trackHeight > 0, scrollRange > 0.5 else {
            persistentIndicator.isHidden = true
            return
        }

        let thumbHeight = min(trackHeight, max(minimumIndicatorHeight, trackHeight * visibleHeight / contentSize.height))
        let progress = min(1, max(0, (contentOffset.y + insets.top) / scrollRange))
        // Subview coordinates include the content offset, keeping the thumb
        // pinned to the viewport during scrolling and rubber-band overscroll.
        persistentIndicator.frame = CGRect(
            x: bounds.maxX - indicatorInset - indicatorWidth,
            y: bounds.minY + insets.top + indicatorInset + (trackHeight - thumbHeight) * progress,
            width: indicatorWidth,
            height: thumbHeight
        )
        persistentIndicator.isHidden = false
        bringSubviewToFront(persistentIndicator)
    }
}
