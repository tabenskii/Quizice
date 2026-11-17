import UIKit

/// Keeps the scroll position visible even while the reader is not dragging.
final class PersistentScrollIndicatorScrollView: UIScrollView {
    static let indicatorGutter: CGFloat = 10
    private let persistentIndicator = PersistentScrollIndicatorView()

    var persistentIndicatorColor: UIColor = .secondaryLabel {
        didSet { persistentIndicator.backgroundColor = persistentIndicatorColor }
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
        contentInsetAdjustmentBehavior = .never
        persistentIndicator.attach(to: self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        persistentIndicator.updatePosition()
    }
}

final class PersistentScrollIndicatorView: UIView {
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private let indicatorWidth: CGFloat = 3
    private let indicatorInset: CGFloat = 2
    private let minimumIndicatorHeight: CGFloat = 24

    init() {
        super.init(frame: .zero)
        accessibilityIdentifier = "persistentScrollIndicator"
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        backgroundColor = .secondaryLabel
        layer.cornerRadius = indicatorWidth / 2
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.addSubview(self)
        observations = [
            scrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.updatePosition() },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.updatePosition() },
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.updatePosition() }
        ]
        updatePosition()
    }

    func detach() {
        observations.removeAll()
        scrollView = nil
        removeFromSuperview()
    }

    func updatePosition() {
        guard let scrollView else { return }
        let insets = scrollView.adjustedContentInset
        let bounds = scrollView.bounds
        let contentSize = scrollView.contentSize
        let visibleHeight = bounds.height - insets.top - insets.bottom
        let scrollRange = contentSize.height - visibleHeight
        let trackHeight = visibleHeight - indicatorInset * 2
        guard bounds.width > 0, trackHeight > 0, scrollRange > 0.5 else {
            isHidden = true
            return
        }

        let thumbHeight = min(trackHeight, max(minimumIndicatorHeight, trackHeight * visibleHeight / contentSize.height))
        let progress = min(1, max(0, (scrollView.contentOffset.y + insets.top) / scrollRange))
        frame = CGRect(
            x: bounds.maxX - indicatorInset - indicatorWidth,
            y: bounds.minY + insets.top + indicatorInset + (trackHeight - thumbHeight) * progress,
            width: indicatorWidth,
            height: thumbHeight
        )
        isHidden = false
        scrollView.bringSubviewToFront(self)
    }
}
