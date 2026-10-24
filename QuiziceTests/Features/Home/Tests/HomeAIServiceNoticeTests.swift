import UIKit
import XCTest
@testable import Quizice

@MainActor
final class HomeAIServiceNoticeTests: HomeScreenVisualStateTestCase {
    func testDelayedNoticeDoesNotBlockOpeningOrEditingTheCard() async throws {
        let api = HomeAIServiceStatusStub()
        defer { api.failPendingRequests() }
        let viewController = makeHomeViewController(api: api)
        let cardView = try await openAIThemeCard(in: viewController)
        try await waitUntil { api.requestedLocales.count == 1 }
        let noticeTask = try XCTUnwrap(viewController.aiServiceNoticeTask)

        XCTAssertTrue(cardView.frontServiceNoticeLabel.isHidden)
        XCTAssertTrue(cardView.promptTextView.isEditable)
        cardView.promptTextView.text = "Космос"
        cardView.textViewDidChange(cardView.promptTextView)
        XCTAssertTrue(cardView.playButton.isEnabled)

        try api.completeRequest(at: 0, with: .success("Сейчас вопросы создаются с задержкой."))
        await noticeTask.value

        XCTAssertTrue(viewController.expandedAIThemeCardView === cardView)
        XCTAssertEqual(cardView.promptTextView.text, "Космос")
        XCTAssertTrue(cardView.playButton.isEnabled)
        XCTAssertEqual(cardView.frontServiceNoticeLabel.text, "Сейчас вопросы создаются с задержкой.")
        XCTAssertEqual(cardView.backServiceNoticeLabel.text, cardView.frontServiceNoticeLabel.text)
        XCTAssertFalse(cardView.frontServiceNoticeLabel.isHidden)
        XCTAssertEqual(api.requestedLocales, ["ru"])
    }

    func testMissingNoticeOrFailedRequestLeavesCardUsableWithoutAnAlert() async throws {
        let responses: [Result<String?, Error>] = [
            .success(nil),
            .failure(URLError(.timedOut))
        ]
        for response in responses {
            let api = HomeAIServiceStatusStub()
            defer { api.failPendingRequests() }
            let viewController = makeHomeViewController(api: api)
            let cardView = try await openAIThemeCard(in: viewController)
            try await waitUntil { api.requestedLocales.count == 1 }
            let noticeTask = try XCTUnwrap(viewController.aiServiceNoticeTask)

            try api.completeRequest(at: 0, with: response)
            await noticeTask.value

            XCTAssertTrue(viewController.expandedAIThemeCardView === cardView)
            XCTAssertTrue(cardView.frontServiceNoticeLabel.isHidden)
            XCTAssertTrue(cardView.backServiceNoticeLabel.isHidden)
            XCTAssertNil(cardView.frontServiceNoticeLabel.text)
            XCTAssertNil(viewController.aiAlertPresenter.alertViewController)
            XCTAssertTrue(cardView.promptTextView.isEditable)
            cardView.promptTextView.text = "Космос"
            cardView.textViewDidChange(cardView.promptTextView)
            XCTAssertTrue(cardView.playButton.isEnabled)
            XCTAssertTrue(cardView.submitButton.isEnabled)
        }
    }

    func testReopeningFetchesAgainAndIgnoresTheClosedCardsLateResponse() async throws {
        let api = HomeAIServiceStatusStub()
        defer { api.failPendingRequests() }
        let viewController = makeHomeViewController(api: api)
        let firstCard = try await openAIThemeCard(in: viewController)
        try await waitUntil { api.requestedLocales.count == 1 }
        let firstTask = try XCTUnwrap(viewController.aiServiceNoticeTask)

        firstCard.closeButton.sendActions(for: .touchUpInside)
        try await waitUntil {
            viewController.expandedAIThemeCardView == nil && viewController.homeCardState.phase == .grid
        }
        XCTAssertNil(viewController.expandedAIThemeCardView)

        let secondCard = try await openAIThemeCard(in: viewController)
        try await waitUntil { api.requestedLocales.count == 2 }
        let secondTask = try XCTUnwrap(viewController.aiServiceNoticeTask)
        XCTAssertFalse(firstCard === secondCard)
        try api.completeRequest(at: 1, with: .success("Актуальное сообщение"))
        await secondTask.value
        try api.completeRequest(at: 0, with: .success("Устаревшее сообщение"))
        await firstTask.value

        XCTAssertEqual(api.requestedLocales, ["ru", "ru"])
        XCTAssertEqual(secondCard.frontServiceNoticeLabel.text, "Актуальное сообщение")
        XCTAssertEqual(secondCard.backServiceNoticeLabel.text, "Актуальное сообщение")
        XCTAssertNil(firstCard.frontServiceNoticeLabel.text)
    }

    private func makeHomeViewController(api: AIServiceStatusAPI) -> QuizViewController {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let viewController = QuizViewController(
            aiServiceStatusAPI: api,
            cardReduceMotionProvider: { true }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        return viewController
    }

    private func openAIThemeCard(in viewController: QuizViewController) async throws -> ExpandedAIThemeCardView {
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeCreateWithAIButton") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }
        return try XCTUnwrap(viewController.expandedAIThemeCardView)
    }
}

@MainActor
private final class HomeAIServiceStatusStub: AIServiceStatusAPI {
    private(set) var requestedLocales: [String] = []
    private var continuations: [CheckedContinuation<String?, Error>?] = []

    func fetchNotice(locale: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            requestedLocales.append(locale)
            continuations.append(continuation)
        }
    }

    func completeRequest(at index: Int, with result: Result<String?, Error>) throws {
        let continuation = try XCTUnwrap(
            continuations.indices.contains(index) ? continuations[index] : nil
        )
        continuations[index] = nil
        continuation.resume(with: result)
    }

    func failPendingRequests() {
        for continuation in continuations {
            continuation?.resume(throwing: CancellationError())
        }
        continuations = []
    }
}
