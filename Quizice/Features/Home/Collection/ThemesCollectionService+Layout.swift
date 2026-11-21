import UIKit

struct HomeThemeScrollAnchor {
    let themeID: String
    let offsetFromTop: CGFloat
}

extension ThemesCollectionService {
    func captureScrollAnchor() {
        guard pendingScrollAnchor == nil,
              let catalog = themeItemsCollectionView,
              let outer = observedCollectionView else { return }
        let scroller = usesOuterScrolling ? outer : catalog
        let visibleTop = scroller.contentOffset.y + scroller.adjustedContentInset.top
        let visibleBottom = scroller.contentOffset.y + scroller.bounds.height
        let candidates = catalog.indexPathsForVisibleItems.compactMap { indexPath -> (Int, CGRect)? in
            guard let attributes = catalog.layoutAttributesForItem(at: indexPath) else { return nil }
            let frame = catalog.convert(attributes.frame, to: scroller)
            guard frame.maxY > visibleTop, frame.minY < visibleBottom else { return nil }
            return (indexPath.item, frame)
        }.sorted { left, right in
            left.1.minY == right.1.minY ? left.0 < right.0 : left.1.minY < right.1.minY
        }
        guard let first = candidates.first, let theme = displayedThemes[safe: first.0] else { return }
        pendingScrollAnchor = HomeThemeScrollAnchor(themeID: theme.stableID, offsetFromTop: first.1.minY - visibleTop)
    }

    func restoreScrollAnchor() {
        guard let anchor = pendingScrollAnchor,
              let catalog = themeItemsCollectionView,
              let outer = observedCollectionView else { return }
        pendingScrollAnchor = nil
        guard let index = displayedThemes.firstIndex(where: { $0.stableID == anchor.themeID }) else { return }
        catalog.layoutIfNeeded()
        guard let attributes = catalog.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
        let scroller = usesOuterScrolling ? outer : catalog
        let frame = catalog.convert(attributes.frame, to: scroller)
        let minimum = -scroller.adjustedContentInset.top
        let maximum = max(minimum, scroller.contentSize.height - scroller.bounds.height + scroller.adjustedContentInset.bottom)
        let offset = min(maximum, max(minimum, frame.minY - anchor.offsetFromTop - scroller.adjustedContentInset.top))
        scroller.setContentOffset(CGPoint(x: scroller.contentOffset.x, y: offset), animated: false)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if isThemeItemsCollectionView(collectionView) {
            let grid = themeGrid(width: collectionView.bounds.width, traits: collectionView.traitCollection)
            return CGSize(
                width: grid.cardWidth,
                height: displayedThemes[safe: indexPath.item].map { grid.cardHeight(title: $0.theme) }
                    ?? ThemeCardLayoutMetrics.singleLineHeight
            )
        }

        let availableWidth = max(
            collectionView.bounds.width - Layout.sectionInsets.left - Layout.sectionInsets.right,
            0
        )
        if indexPath.item == themesViewportIndex {
            return CGSize(
                width: availableWidth,
                height: themesViewportHeight(
                    width: availableWidth,
                    traitCollection: collectionView.traitCollection,
                    availableOuterHeight: availableContentHeight(in: collectionView)
                )
            )
        }

        if indexPath.item == statisticsIndex {
            return CGSize(
                width: availableWidth,
                height: Layout.statisticsCardHeight
                    + lastItemBottomInset(availableHeight: availableContentHeight(in: collectionView))
            )
        }

        if let subscriptionPromoIndex, indexPath.item == subscriptionPromoIndex {
            let height = collectionView.traitCollection.preferredContentSizeCategory
                .isAccessibilityCategory
                ? Layout.accessibilitySubscriptionPromoHeight
                : Layout.subscriptionPromoHeight
            return CGSize(width: availableWidth, height: height)
        }

        if indexPath.item == aiThemeIndex {
            return CGSize(width: availableWidth, height: aiThemeCardHeight(
                width: min(availableWidth, 640), traits: collectionView.traitCollection
            ))
        }

        if indexPath.item == feelingLuckyIndex {
            return CGSize(width: availableWidth, height: Layout.secondaryActionButtonHeight)
        }

        return CGSize(width: availableWidth, height: Layout.secondaryActionButtonHeight)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        isThemeItemsCollectionView(collectionView)
            ? Layout.itemSpacing
            : outerItemSpacing(availableHeight: availableContentHeight(in: collectionView))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        isThemeItemsCollectionView(collectionView)
            ? Layout.itemSpacing
            : outerItemSpacing(availableHeight: availableContentHeight(in: collectionView))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        isThemeItemsCollectionView(collectionView) ? .zero : Layout.sectionInsets
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        guard !isThemeItemsCollectionView(collectionView) else { return .zero }
        let width = collectionView.bounds.width
        let contentWidth = width - Layout.sectionInsets.left - Layout.sectionInsets.right
        let height = maintenanceBannerHeight(width: contentWidth, traits: collectionView.traitCollection,
            availableHeight: availableContentHeight(in: collectionView))
        return CGSize(width: width, height: height)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let collectionView = scrollView as? UICollectionView,
           isThemeItemsCollectionView(collectionView) {
            updateMoreThemesButtonVisibility(animated: true)
            return
        }
        delegate?.themesCollectionDidScroll(scrollView)
    }

    func themeGrid(width: CGFloat, traits: UITraitCollection) -> ThemeCardLayoutMetrics.Grid {
        let font = appearanceStore.appearance(compatibleWith: traits).typography.font(
            size: ThemeCardLayoutMetrics.titleFontSize, weight: .semibold, compatibleWith: traits
        )
        return ThemeCardLayoutMetrics.grid(
            titles: displayedThemes.map(\.theme), width: width, spacing: Layout.itemSpacing,
            font: font, traitCollection: traits,
            preferredColumnCount: AppAdaptiveLayout(
                width: observedCollectionView?.bounds.width ?? width + 48
            ).preferredThemeColumns
        )
    }

    func themeMasonryGeometry(in collectionView: UICollectionView) -> HomeThemeMasonryGeometry {
        let grid = themeGrid(width: collectionView.bounds.width, traits: collectionView.traitCollection)
        return themeMasonryGeometry(width: collectionView.bounds.width, grid: grid)
    }

    private func themeMasonryGeometry(width: CGFloat, grid: ThemeCardLayoutMetrics.Grid) -> HomeThemeMasonryGeometry {
        HomeThemeMasonryGeometry(
            itemHeights: displayedThemes.map { grid.cardHeight(title: $0.theme) },
            columnCount: grid.columnCount, cardWidth: grid.cardWidth,
            spacing: Layout.itemSpacing, width: width
        )
    }

    func isThemeItemsCollectionView(_ collectionView: UICollectionView) -> Bool {
        collectionView === themeItemsCollectionView
            || collectionView.accessibilityIdentifier == Content.themeCatalogAccessibilityID
    }

    private func themesViewportHeight(
        width: CGFloat,
        traitCollection: UITraitCollection,
        availableOuterHeight: CGFloat
    ) -> CGFloat {
        let grid = themeGrid(width: width, traits: traitCollection)
        let geometry = themeMasonryGeometry(width: width, grid: grid)
        let usesAccessibilityLayout = traitCollection
            .preferredContentSizeCategory
            .isAccessibilityCategory
        let fixedOuterContentHeight =
            (showsSubscriptionPromo
                ? (usesAccessibilityLayout
                    ? Layout.accessibilitySubscriptionPromoHeight
                    : Layout.subscriptionPromoHeight)
                : 0)
            + aiThemeCardHeight(width: min(width, 640), traits: traitCollection)
            + Layout.secondaryActionButtonHeight
            + Layout.statisticsCardHeight
            + lastItemBottomInset(availableHeight: availableOuterHeight)
            + outerItemSpacing(availableHeight: availableOuterHeight)
                * CGFloat(outerItemCount - 1)
        let viewportBudget = availableOuterHeight - fixedOuterContentHeight
            - maintenanceBannerHeight(width: width, traits: traitCollection, availableHeight: availableOuterHeight)
        let minimumViewportHeight = geometry.frames.prefix(grid.columnCount).map(\.maxY).max()
            ?? ThemeCardLayoutMetrics.singleLineHeight
        usesOuterScrolling = usesAccessibilityLayout
            || minimumViewportHeight > viewportBudget
        if usesOuterScrolling {
            catalogCanScroll = false
            return geometry.contentSize.height
        }

        let maximumViewportHeight = geometry.frames
            .prefix(Layout.viewportCardsPerColumn * grid.columnCount)
            .map(\.maxY).max() ?? minimumViewportHeight
        let viewportHeight = min(maximumViewportHeight, max(viewportBudget, minimumViewportHeight))
        catalogCanScroll = geometry.contentSize.height > viewportHeight + 0.5
        return viewportHeight
    }

    private func availableContentHeight(in collectionView: UICollectionView) -> CGFloat {
        max(
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom,
            0
        )
    }

    func maintenanceBannerSpacing(in collectionView: UICollectionView) -> CGFloat {
        outerItemSpacing(availableHeight: availableContentHeight(in: collectionView))
    }

    private func maintenanceBannerHeight(width: CGFloat, traits: UITraitCollection, availableHeight: CGFloat) -> CGFloat {
        guard let maintenanceNotice, width > 0 else { return 0 }
        return HomeMaintenanceBannerView.height(message: maintenanceNotice, width: width,
            appearance: appearanceStore.appearance(compatibleWith: traits), traits: traits)
            + outerItemSpacing(availableHeight: availableHeight)
    }

    private func outerItemSpacing(availableHeight: CGFloat) -> CGFloat {
        availableHeight < Layout.compactAvailableHeightThreshold
            ? Layout.compactOuterItemSpacing
            : Layout.itemSpacing
    }

    func lastItemBottomInset(availableHeight: CGFloat) -> CGFloat {
        availableHeight < Layout.compactAvailableHeightThreshold
            ? Layout.compactLastItemBottomInset
            : Layout.lastItemBottomInset
    }

    func updateThemeCatalogScrollAvailability() {
        guard let themeItemsCollectionView else { return }
        let canScroll = !usesOuterScrolling && catalogCanScroll
        themeItemsCollectionView.isScrollEnabled = canScroll
        themeItemsCollectionView.alwaysBounceVertical = canScroll
        themeItemsCollectionView.bounces = canScroll
        if usesOuterScrolling {
            themeItemsCollectionView.setContentOffset(.zero, animated: false)
        }
    }

}
