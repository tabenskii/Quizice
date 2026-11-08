import UIKit

final class ThemesCollectionService: NSObject, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    enum Content {
        static let themeCellReuseIdentifier = "themeCell"
        static let themeImageAccessibilityIDPrefix = "homeThemeImageView"
        static let themeTitleAccessibilityIDPrefix = "homeThemeTitleLabel"
        static let themeCatalogAccessibilityID = "homeThemeCatalogCollectionView"
        static let moreThemesAccessibilityID = "homeMoreThemesButton"
        static let aiThemeAccessibilityID = "homeCreateWithAIButton"
        static let aiThemeTextStackAccessibilityID = "homeCreateWithAITextStack"
        static let aiThemeTitleAccessibilityID = "homeCreateWithAITitle"
        static let aiThemeBadgeAccessibilityID = "homeCreateWithAIBadge"
        static let aiThemeSubtitleAccessibilityID = "homeCreateWithAISubtitle"
        static let aiThemeGradientBorderAccessibilityID = "homeCreateWithAIGradientBorder"
        static let feelingLuckyAccessibilityID = "homeFeelingLuckyButton"
        static let feelingLuckyProgressAccessibilityID = "homeFeelingLuckyProgressView"
        static let statisticsAccessibilityID = "homeStatisticsCard"
        static let statisticsTitleAccessibilityID = "homeStatisticsTitleLabel"
        static let statisticsDescriptionAccessibilityID = "homeStatisticsDescriptionLabel"
        static let statisticsPlayedValueAccessibilityID = "homeStatisticsPlayedValueLabel"
        static let statisticsPlayedTitleAccessibilityID = "homeStatisticsPlayedTitleLabel"
        static let statisticsAccuracyValueAccessibilityID = "homeStatisticsAccuracyValueLabel"
        static let statisticsAccuracyTitleAccessibilityID = "homeStatisticsAccuracyTitleLabel"
    }

    enum Layout {
        static let sectionInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        static let itemSpacing: CGFloat = 16
        static let compactOuterItemSpacing: CGFloat = 12
        static let visibleThemeRowCount = 4
        static let prominentActionCardHeight: CGFloat = 72
        static let accessibilityProminentActionCardHeight: CGFloat = 272
        static let aiThemeButtonHeight = prominentActionCardHeight
        static let secondaryActionButtonHeight: CGFloat = 54
        static let subscriptionPromoHeight = prominentActionCardHeight
        static let accessibilitySubscriptionPromoHeight = accessibilityProminentActionCardHeight
        static let statisticsCardHeight: CGFloat = 112
        static let lastItemBottomInset: CGFloat = 24
        static let compactLastItemBottomInset: CGFloat = 16
        static let compactAvailableHeightThreshold: CGFloat = 600
        static let aiThemeBadgeTrailingInset: CGFloat = 16
        static let aiThemeContentLeadingInset: CGFloat = 18
        static let aiThemeContentTrailingSpacing: CGFloat = 12
        static let aiThemeBadgeHorizontalInset: CGFloat = 10
        static let aiThemeBadgeVerticalInset: CGFloat = 5
        static let aiThemeBadgeMinimumWidth: CGFloat = 52
        static let cellShadowOffset = CGSize(width: 0, height: 12)
        static let cellShadowRadius: CGFloat = 22
        static let moreThemesButtonHeight: CGFloat = 82
        static let moreThemesVisibilityThreshold: CGFloat = 5
    }

    enum Appearance {
        static let themeCardBackgroundAlpha: CGFloat = 0.20
        static let themeCardBorderAlpha: CGFloat = 0.45
        static let feelingLuckyButtonBackgroundAlpha: CGFloat = 0.14
        static let feelingLuckyButtonBorderAlpha: CGFloat = 0.36
        static let feelingLuckyButtonCornerRadius: CGFloat = 20
        static let buttonBorderWidth: CGFloat = 1
        static let aiThemeGradientBorderWidth: CGFloat = 1.6
        static let radarAIThemeGlowOpacity: Float = 0.22
        static let radarAIThemeGlowRadius: CGFloat = 10
        static let radarAIThemeGlowOffset = CGSize(width: 0, height: 0)
        static let aiThemeBadgeBackgroundAlpha: CGFloat = 0.18
        static let aiThemeBadgeBorderAlpha: CGFloat = 0.52
        static let aiThemeBadgeCornerRadius: CGFloat = 11
        static let cellShadowOpacity: Float = 0.22
        static let titleFontSize: CGFloat = 24
        static let descriptionFontSize: CGFloat = 15
        static let luckyFontSize: CGFloat = 19
        static let aiThemeTitleFontSize: CGFloat = 18
        static let aiThemeSubtitleFontSize: CGFloat = 12
        static let aiThemeBadgeFontSize: CGFloat = 11
    }

    weak var delegate: ThemeCollectionDelegate?

    var presentedThemeID: String? {
        didSet {
            guard oldValue != presentedThemeID else { return }
            reconfigureThemeCells(withIDs: [oldValue, presentedThemeID].compactMap { $0 })
        }
    }

    var isStatisticsPresented = false {
        didSet {
            guard oldValue != isStatisticsPresented else { return }
            reconfigureStatisticsCell()
        }
    }

    var isAIThemePresented = false {
        didSet {
            guard oldValue != isAIThemePresented else { return }
            reconfigureAIThemeCell()
        }
    }

    var isFeelingLuckyLoading = false {
        didSet {
            guard oldValue != isFeelingLuckyLoading else { return }
            refreshVisibleFeelingLuckyButton()
        }
    }

    private let themeRepository: ThemeRepository
    private let statisticsStore: StatisticsStore
    private let subscriptionEntitlementProvider: SubscriptionEntitlementProviding
    private let preferredThemeIDsProvider: () -> [String]?
    let appearanceStore = AppAppearanceStore.shared
    var hasActivePlusSubscription: Bool
    private var subscriptionEntitlementObserver: NSObjectProtocol?
    weak var observedCollectionView: UICollectionView?
    weak var themeItemsCollectionView: UICollectionView?
    private weak var moreThemesButton: MoreThemesFadeButton?
    private weak var moreThemesTapGestureRecognizer: UITapGestureRecognizer?

    var pendingScrollAnchor: HomeThemeScrollAnchor?

    var usesOuterScrolling = false {
        didSet {
            guard oldValue != usesOuterScrolling else { return }
            updateThemeCatalogScrollAvailability()
            configureMoreThemesButton()
            observedCollectionView?.isScrollEnabled = usesOuterScrolling
            observedCollectionView?.bounces = usesOuterScrolling
            if !usesOuterScrolling, let collectionView = observedCollectionView {
                collectionView.setContentOffset(
                    CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false
                )
            }
        }
    }

    var catalogCollectionView: UICollectionView? {
        themeItemsCollectionView
    }

    var visibleThemeCells: [ThemeCardCollectionViewCell] {
        themeItemsCollectionView?.visibleCells.compactMap {
            $0 as? ThemeCardCollectionViewCell
        } ?? []
    }

    func revealThemeButton(themeID: String) -> UIButton? {
        guard let collectionView = themeItemsCollectionView,
              let index = displayedThemes.firstIndex(where: { $0.stableID == themeID }) else { return nil }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
        return (collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ThemeCardCollectionViewCell)?.actionButton
    }

    var displayedThemes: [QuizTheme] {
        let themes = themeRepository.themes ?? []
        let preferredThemeIDs = preferredThemeIDsProvider()
            ?? themes.filter(\.isFavorite).map(\.stableID)
        return Self.orderedThemes(themes, preferredThemeIDs: preferredThemeIDs)
    }

    var visibleThemeLimit: Int {
        activeViewportRowCount * activeThemeColumnCount
    }

    private var showsMoreThemesButton: Bool {
        !usesOuterScrolling && displayedThemes.count > visibleThemeLimit
    }

    var themeCount: Int { displayedThemes.count }
    var activeThemeColumnCount = 2 {
        didSet {
            guard oldValue != activeThemeColumnCount else { return }
            updateThemeCatalogScrollAvailability()
            configureMoreThemesButton()
        }
    }
    var activeViewportRowCount = Layout.visibleThemeRowCount {
        didSet {
            guard oldValue != activeViewportRowCount else { return }
            updateThemeCatalogScrollAvailability()
            configureMoreThemesButton()
        }
    }

#if DEBUG
    var showsSubscriptionPromo = UserDefaults.standard.bool(forKey: DebugSubscriptionPromoSettings.showPromoKey) {
        didSet {
            guard oldValue != showsSubscriptionPromo else { return }
            observedCollectionView?.reloadData()
            observedCollectionView?.collectionViewLayout.invalidateLayout()
        }
    }
#else
    let showsSubscriptionPromo = false
#endif

    let themesViewportIndex = 0
    var subscriptionPromoIndex: Int? { showsSubscriptionPromo ? 1 : nil }
    var aiThemeIndex: Int { showsSubscriptionPromo ? 2 : 1 }
    var feelingLuckyIndex: Int { showsSubscriptionPromo ? 3 : 2 }
    var statisticsIndex: Int { showsSubscriptionPromo ? 4 : 3 }
    var outerItemCount: Int { showsSubscriptionPromo ? 5 : 4 }

    init(
        themeRepository: ThemeRepository = QuizFactory.shared,
        statisticsStore: StatisticsStore = StatisticsStore(),
        subscriptionEntitlementProvider: SubscriptionEntitlementProviding =
            SubscriptionEntitlementStore.shared,
        preferredThemeIDsProvider: @escaping () -> [String]? = {
            OnboardingProgressStore.shared.storedPreferredThemeIDs(
                locale: AppLocalizationStore.shared.resolvedLanguageCode
            )
        }
    ) {
        self.themeRepository = themeRepository
        self.statisticsStore = statisticsStore
        self.subscriptionEntitlementProvider = subscriptionEntitlementProvider
        self.hasActivePlusSubscription =
            subscriptionEntitlementProvider.hasActivePlusSubscription
        self.preferredThemeIDsProvider = preferredThemeIDsProvider
        super.init()
        subscriptionEntitlementObserver = NotificationCenter.default.addObserver(
            forName: .subscriptionEntitlementDidChange,
            object: subscriptionEntitlementProvider,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSubscriptionEntitlement()
        }
    }

    deinit {
        if let subscriptionEntitlementObserver {
            NotificationCenter.default.removeObserver(subscriptionEntitlementObserver)
        }
    }

    func refreshStatistics() {
        reconfigureStatisticsCell()
    }

    private func refreshSubscriptionEntitlement() {
        let newValue = subscriptionEntitlementProvider.hasActivePlusSubscription
        guard hasActivePlusSubscription != newValue else { return }
        hasActivePlusSubscription = newValue

        guard let collectionView = observedCollectionView else { return }
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isThemeItemsCollectionView(collectionView) {
            themeItemsCollectionView = collectionView
            return themeCount
        }
        observedCollectionView = collectionView
        return outerItemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let appearance = appearanceStore.appearance(compatibleWith: collectionView.traitCollection)

        if isThemeItemsCollectionView(collectionView) {
            themeItemsCollectionView = collectionView
            guard let theme = displayedThemes[safe: indexPath.item] else {
                preconditionFailure("Expected catalog theme at \(indexPath)")
            }
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ThemeCardCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? ThemeCardCollectionViewCell else {
                preconditionFailure("Expected ThemeCardCollectionViewCell for catalog theme")
            }
            cell.configure(
                theme: theme,
                appearance: appearance,
                isSourceHidden: theme.stableID == presentedThemeID,
                grid: themeGrid(width: collectionView.bounds.width, traits: collectionView.traitCollection)
            )
            cell.actionButton.removeTarget(self, action: nil, for: .allEvents)
            cell.actionButton.addTarget(self, action: #selector(buttonTouchedDown(_:)), for: .touchDown)
            cell.actionButton.addTarget(self, action: #selector(buttonTouchedUpInside(_:)), for: .touchUpInside)
            cell.actionButton.addTarget(self, action: #selector(buttonTouchedUpOutside(_:)), for: .touchUpOutside)
            return cell
        }

        observedCollectionView = collectionView
        if indexPath.item == themesViewportIndex {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ThemesViewportCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? ThemesViewportCollectionViewCell else {
                preconditionFailure("Expected ThemesViewportCollectionViewCell")
            }
            themeItemsCollectionView = cell.themesCollectionView
            cell.configure(
                dataSource: self,
                delegate: self,
                canScroll: !usesOuterScrolling && displayedThemes.count > visibleThemeLimit
            )
            installMoreThemesButtonIfNeeded(in: cell)
            configureMoreThemesButton()
            return cell
        }

        if let subscriptionPromoIndex, indexPath.item == subscriptionPromoIndex {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SubscriptionPromoBannerCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? SubscriptionPromoBannerCollectionViewCell else {
                preconditionFailure("Expected SubscriptionPromoBannerCollectionViewCell")
            }
            cell.configure(appearance: appearance)
            cell.actionButton.removeTarget(self, action: nil, for: .allEvents)
            cell.actionButton.addTarget(
                self,
                action: #selector(buttonTouchedDown(_:)),
                for: .touchDown
            )
            cell.actionButton.addTarget(
                self,
                action: #selector(subscriptionPromoButtonTouchedUpInside(_:)),
                for: .touchUpInside
            )
            cell.actionButton.addTarget(
                self,
                action: #selector(buttonTouchedUpOutside(_:)),
                for: .touchUpOutside
            )
            return cell
        }

        if indexPath.item == statisticsIndex {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StatisticsCardCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? StatisticsCardCollectionViewCell else {
                preconditionFailure("Expected StatisticsCardCollectionViewCell")
            }
            cell.configure(
                summary: statisticsStore.loadSummary(),
                appearance: appearance,
                isSourceHidden: isStatisticsPresented
            )
            cell.actionButton.removeTarget(self, action: nil, for: .allEvents)
            cell.actionButton.addTarget(self, action: #selector(buttonTouchedDown(_:)), for: .touchDown)
            cell.actionButton.addTarget(self, action: #selector(statisticsButtonTouchedUpInside(_:)), for: .touchUpInside)
            cell.actionButton.addTarget(self, action: #selector(buttonTouchedUpOutside(_:)), for: .touchUpOutside)
            return cell
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Content.themeCellReuseIdentifier,
            for: indexPath
        )
        prepare(cell, appearance: appearance)

        if indexPath.item == feelingLuckyIndex {
            configureFeelingLuckyCard(in: cell, appearance: appearance)
            return cell
        }

        if indexPath.item == aiThemeIndex {
            configureAIThemeCard(in: cell, appearance: appearance, traits: collectionView.traitCollection)
            return cell
        }

        return cell
    }

    private func prepare(_ cell: UICollectionViewCell, appearance: AppAppearance) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentView.backgroundColor = .clear
        cell.contentView.clipsToBounds = false
        cell.backgroundColor = .clear
        cell.layer.masksToBounds = false
        cell.applyShadow(appearance.themeCardShadow)
    }

    private func reconfigureThemeCells(withIDs themeIDs: [String]) {
        guard
            let collectionView = themeItemsCollectionView,
            !themeIDs.isEmpty
        else {
            return
        }

        let identifiers = Set(themeIDs)
        let indexPaths = displayedThemes.enumerated().compactMap { index, theme in
            identifiers.contains(theme.stableID) ? IndexPath(item: index, section: 0) : nil
        }
        guard !indexPaths.isEmpty else { return }

        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: indexPaths)
        }
    }

    private func reconfigureStatisticsCell() {
        guard let collectionView = observedCollectionView else { return }
        let indexPath = IndexPath(item: statisticsIndex, section: 0)
        guard collectionView.numberOfItems(inSection: 0) > indexPath.item else { return }

        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [indexPath])
        }
    }

    private func reconfigureAIThemeCell() {
        guard let collectionView = observedCollectionView else { return }
        let indexPath = IndexPath(item: aiThemeIndex, section: 0)
        guard collectionView.numberOfItems(inSection: 0) > indexPath.item else { return }

        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [indexPath])
        }
    }

    private func installMoreThemesButtonIfNeeded(in cell: ThemesViewportCollectionViewCell) {
        let collectionView = cell.themesCollectionView
        if moreThemesButton?.superview === cell.contentView {
            return
        }

        moreThemesButton?.removeFromSuperview()
        if let previousTapGesture = moreThemesTapGestureRecognizer {
            previousTapGesture.view?.removeGestureRecognizer(previousTapGesture)
        }

        let button = MoreThemesFadeButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        // The visual overlay must not participate in hit testing: touches then
        // reach the collection view underneath and its native pan gesture keeps
        // scrolling with full momentum. A dedicated tap recognizer below keeps
        // the "More themes" action available without putting the label under
        // the collection view's fade mask.
        button.isUserInteractionEnabled = false
        button.addTarget(self, action: #selector(moreThemesButtonTapped), for: .touchUpInside)
        cell.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: Layout.moreThemesButtonHeight)
        ])

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(moreThemesOverlayTapped(_:))
        )
        tapGesture.delegate = self
        collectionView.addGestureRecognizer(tapGesture)

        moreThemesButton = button
        moreThemesTapGestureRecognizer = tapGesture
    }

    func configureMoreThemesButton() {
        guard let button = moreThemesButton else { return }
        guard showsMoreThemesButton else {
            button.setVisible(false, animated: false)
            (themeItemsCollectionView as? HomeThemesCollectionView)?
                .updateBottomFade(visibility: 0, height: 0)
            return
        }
        guard let collectionView = themeItemsCollectionView else { return }
        button.configure(
            appearance: appearanceStore.appearance(compatibleWith: collectionView.traitCollection)
        )
        updateMoreThemesButtonVisibility(animated: false)
    }

    func updateMoreThemesButtonVisibility(animated: Bool) {
        guard
            showsMoreThemesButton,
            let collectionView = themeItemsCollectionView,
            let button = moreThemesButton
        else { return }

        let distanceFromTop = collectionView.contentOffset.y
            + collectionView.adjustedContentInset.top
        let isVisible = distanceFromTop < Layout.moreThemesVisibilityThreshold
        button.setVisible(isVisible, animated: animated)
        (collectionView as? HomeThemesCollectionView)?.updateBottomFade(
            visibility: isVisible ? 1 : 0,
            height: Layout.moreThemesButtonHeight,
            animated: animated
        )
        if !button.isHidden {
            button.superview?.bringSubviewToFront(button)
        }
    }

    @objc private func moreThemesButtonTapped() {
        guard
            showsMoreThemesButton,
            let collectionView = themeItemsCollectionView,
            collectionView.numberOfItems(inSection: 0) > visibleThemeLimit
        else { return }

        collectionView.scrollToItem(
            at: IndexPath(item: visibleThemeLimit, section: 0),
            at: .top,
            animated: true
        )
    }

    @objc private func moreThemesOverlayTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        moreThemesButtonTapped()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === moreThemesTapGestureRecognizer else { return true }
        guard
            let button = moreThemesButton,
            !button.isHidden,
            button.alpha > 0.01
        else {
            return false
        }

        let location = touch.location(in: button)
        return button.point(inside: location, with: nil)
    }

    @objc func buttonTouchedDown(_ sender: UIButton) {
        delegate?.themeButtonTouchedDown(sender)
    }

    @objc func buttonTouchedUpInside(_ sender: UIButton) {
        guard
            let themeID = sender.accessibilityIdentifier,
            themeRepository.themes?.contains(where: { $0.stableID == themeID }) == true
        else { return }
        delegate?.themeButtonTouchedUpInside(sender, themeID: themeID)
    }

    @objc func buttonTouchedUpOutside(_ sender: UIButton) {
        delegate?.themeButtonTouchedUpOutside(sender)
    }
}
