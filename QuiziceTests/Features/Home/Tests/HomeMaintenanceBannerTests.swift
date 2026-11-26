import UIKit
import XCTest
@testable import Quizice

@MainActor
final class HomeMaintenanceBannerTests: HomeScreenVisualStateTestCase {
    private let message = "Обновляем сервер. Вернёмся в 03:00."

    func testColdLaunchAndRefreshUseTheLastSuccessfulStatus() async throws {
        let api = MaintenanceStatusStub(result: .success(message))
        let controller = QuizViewController(maintenanceStatusAPI: api)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        testWindows.append(window)
        try await waitUntil { controller.themesCollectionService.maintenanceNotice == self.message }
        controller.view.layoutIfNeeded()

        let banner = try XCTUnwrap(controller.themesCollectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
        ))
        let label = try XCTUnwrap(banner.subviews.first?.subviews.first as? UILabel)
        XCTAssertTrue(label.isAccessibilityElement)
        XCTAssertEqual(label.text, message)
        XCTAssertEqual(label.numberOfLines, 0)

        api.result = .failure(URLError(.timedOut))
        controller.refreshMaintenanceNotice()
        await controller.maintenanceNoticeTask?.value
        XCTAssertEqual(controller.themesCollectionService.maintenanceNotice, message)

        api.result = .success(nil)
        controller.refreshMaintenanceNotice()
        await controller.maintenanceNoticeTask?.value
        controller.view.layoutIfNeeded()
        XCTAssertNil(controller.themesCollectionService.maintenanceNotice)
        XCTAssertTrue(controller.themesCollectionView.visibleSupplementaryViews(
            ofKind: UICollectionView.elementKindSectionHeader
        ).isEmpty)
    }

    func testColdLaunchWithUnavailableAPIShowsNoBanner() async throws {
        let controller = QuizViewController(maintenanceStatusAPI: MaintenanceStatusStub(result: .failure(URLError(.cannotConnectToHost))))
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        await controller.maintenanceNoticeTask?.value
        XCTAssertNil(controller.themesCollectionService.maintenanceNotice)
    }

    func testBannerReservesMoreSpaceAtAccessibilityTextSize() {
        let appearance = SnapshotSupport.appearance(designStyle: .classic)
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(
            HomeMaintenanceBannerView.height(message: message, width: 270, appearance: appearance, traits: large),
            HomeMaintenanceBannerView.height(message: message, width: 270, appearance: appearance, traits: standard)
        )
    }
}

private final class MaintenanceStatusStub: MaintenanceStatusAPI {
    var result: Result<String?, Error>

    init(result: Result<String?, Error>) {
        self.result = result
    }

    func fetchMaintenanceNotice() async throws -> String? {
        try result.get()
    }
}
