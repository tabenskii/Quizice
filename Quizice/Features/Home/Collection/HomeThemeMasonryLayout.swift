import UIKit

struct HomeThemeMasonryGeometry {
    let frames: [CGRect]
    let contentSize: CGSize

    init(itemHeights: [CGFloat], columnCount: Int, cardWidth: CGFloat, spacing: CGFloat, width: CGFloat) {
        var columnBottoms = Array(repeating: CGFloat.zero, count: max(columnCount, 1))
        let horizontalSpacing = columnBottoms.count > 1
            ? max(spacing, (width - CGFloat(columnBottoms.count) * cardWidth) / CGFloat(columnBottoms.count - 1))
            : 0
        var frames: [CGRect] = []
        for height in itemHeights {
            // On equal heights, keep the catalog's leading-to-trailing reading order.
            let column = columnBottoms.indices.min { columnBottoms[$0] < columnBottoms[$1] } ?? 0
            let frame = CGRect(
                x: CGFloat(column) * (cardWidth + horizontalSpacing),
                y: columnBottoms[column],
                width: cardWidth,
                height: height
            )
            frames.append(frame)
            columnBottoms[column] = frame.maxY + spacing
        }
        self.frames = frames
        contentSize = CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }
}

@MainActor
protocol HomeThemeMasonryLayoutDelegate: UICollectionViewDelegate {
    func themeMasonryGeometry(in collectionView: UICollectionView) -> HomeThemeMasonryGeometry
}

final class HomeThemeMasonryLayout: UICollectionViewLayout {
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero

    override func prepare() {
        super.prepare()
        guard let collectionView,
              let delegate = collectionView.delegate as? HomeThemeMasonryLayoutDelegate else {
            attributes = []
            contentSize = .zero
            return
        }

        let geometry = delegate.themeMasonryGeometry(in: collectionView)
        attributes = geometry.frames.enumerated().map { item, frame in
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
            attributes.frame = frame
            return attributes
        }
        contentSize = geometry.contentSize
    }

    override var collectionViewContentSize: CGSize { contentSize }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0 else { return nil }
        return attributes[safe: indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}
