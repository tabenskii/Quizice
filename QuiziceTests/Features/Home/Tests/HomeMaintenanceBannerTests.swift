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

    func testLanguageChangeDiscardsAnInFlightResponseAndRefreshesTheBanner() async throws {
        let api = PendingMaintenanceStatusStub()
        defer { api.failPendingRequests() }
        let controller = QuizViewController(maintenanceStatusAPI: api)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        try await waitUntil { api.requestedLocales == ["ru"] }
        let initialTask = try XCTUnwrap(controller.maintenanceNoticeTask)

        AppLocalizationStore.shared.languagePreference = .english
        try await waitUntil { api.requestedLocales == ["ru", "en"] }
        let localizedTask = try XCTUnwrap(controller.maintenanceNoticeTask)

        try api.completeRequest(for: "ru", with: message)
        await initialTask.value

        XCTAssertNil(controller.themesCollectionService.maintenanceNotice)
        XCTAssertNotNil(controller.maintenanceNoticeTask)

        let translation = "Server maintenance in progress."
        try api.completeRequest(for: "en", with: translation)
        await localizedTask.value

        XCTAssertEqual(api.requestedLocales, ["ru", "en"])
        XCTAssertEqual(controller.themesCollectionService.maintenanceNotice, translation)
        XCTAssertNil(controller.maintenanceNoticeTask)
    }

    func testMaintenanceRequestUsesTheAppLocaleAndAcceptsTheExistingResponseShape() async throws {
        defer { BackendTestURLProtocol.requestHandler = nil }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [BackendTestURLProtocol.self]
        let api = HTTPMaintenanceStatusAPI(
            configuration: BackendConfiguration(baseURL: URL(string: "https://example.invalid/api")!),
            session: URLSession(configuration: sessionConfiguration)
        )
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/maintenance/status")
            XCTAssertEqual(request.url?.query, "locale=fr")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertNil(request.value(forHTTPHeaderField: BackendConfiguration.authorizationHeader))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"active":true,"message":"Maintenance en cours."}"#.utf8))
        }

        let notice = try await api.fetchMaintenanceNotice(locale: "fr")
        XCTAssertEqual(notice, "Maintenance en cours.")
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

    func fetchMaintenanceNotice(locale _: String) async throws -> String? {
        try result.get()
    }
}

@MainActor
private final class PendingMaintenanceStatusStub: MaintenanceStatusAPI {
    private(set) var requestedLocales: [String] = []
    private var pending: [String: CheckedContinuation<String?, Error>] = [:]

    func fetchMaintenanceNotice(locale: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            requestedLocales.append(locale)
            pending[locale] = continuation
        }
    }

    func completeRequest(for locale: String, with message: String) throws {
        let continuation = try XCTUnwrap(pending.removeValue(forKey: locale))
        continuation.resume(returning: message)
    }

    func failPendingRequests() {
        for continuation in pending.values {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()
    }
}
