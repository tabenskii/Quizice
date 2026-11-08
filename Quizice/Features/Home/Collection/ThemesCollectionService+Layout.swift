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
                height: themeRowHeight(containing: indexPath.item, grid: grid)
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

    func themeRowHeight(containing itemIndex: Int, grid: ThemeCardLayoutMetrics.Grid) -> CGFloat {
        let rowStartIndex = (itemIndex / grid.columnCount) * grid.columnCount
        guard rowStartIndex < themeCount else {
            return ThemeCardLayoutMetrics.singleLineHeight
        }
        let rowTitles = displayedThemes[
            rowStartIndex..<min(rowStartIndex + grid.columnCount, themeCount)
        ].map(\.theme)
        return grid.rowHeight(titles: rowTitles)
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
        activeThemeColumnCount = grid.columnCount
        let maximumViewportRowCount = min(Layout.visibleThemeRowCount, max(
            Int(ceil(Double(themeCount) / Double(grid.columnCount))), 1
        ))
        let allRowHeights = (0..<maximumViewportRowCount).map { row in
            themeRowHeight(containing: row * grid.columnCount, grid: grid)
        }
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
        let minimumRowHeight = allRowHeights.first ?? ThemeCardLayoutMetrics.singleLineHeight
        usesOuterScrolling = usesAccessibilityLayout
            || fixedOuterContentHeight + minimumRowHeight > availableOuterHeight
        if usesOuterScrolling {
            let rowCount = Int(ceil(Double(themeCount) / Double(grid.columnCount)))
            activeViewportRowCount = max(rowCount, 1)
            return (0..<rowCount).reduce(CGFloat.zero) { height, row in
                height + themeRowHeight(containing: row * grid.columnCount, grid: grid)
                    + (row > 0 ? Layout.itemSpacing : 0)
            }
        }
        let viewportBudget = max(
            availableOuterHeight - fixedOuterContentHeight,
            ThemeCardLayoutMetrics.singleLineHeight
        )
        var fittedRowCount = 0
        var fittedHeight: CGFloat = 0
        for rowHeight in allRowHeights {
            let candidateHeight = fittedHeight
                + (fittedRowCount > 0 ? Layout.itemSpacing : 0)
                + rowHeight
            guard fittedRowCount == 0 || candidateHeight <= viewportBudget else { break }
            fittedRowCount += 1
            fittedHeight = candidateHeight
        }

        activeViewportRowCount = max(fittedRowCount, 1)
        let maximumViewportHeight = allRowHeights.reduce(0, +)
            + Layout.itemSpacing * CGFloat(max(allRowHeights.count - 1, 0))
        let minimumViewportHeight = allRowHeights.first
            ?? ThemeCardLayoutMetrics.singleLineHeight
        return min(
            maximumViewportHeight,
            max(viewportBudget, minimumViewportHeight)
        )
    }

    private func availableContentHeight(in collectionView: UICollectionView) -> CGFloat {
        max(
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom,
            0
        )
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
        let canScroll = !usesOuterScrolling && displayedThemes.count > visibleThemeLimit
        themeItemsCollectionView.isScrollEnabled = canScroll
        themeItemsCollectionView.alwaysBounceVertical = canScroll
        themeItemsCollectionView.bounces = canScroll
        if usesOuterScrolling {
            themeItemsCollectionView.setContentOffset(.zero, animated: false)
        }
    }

}
