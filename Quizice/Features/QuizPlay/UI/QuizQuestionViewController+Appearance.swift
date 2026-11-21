import UIKit
import AVKit
import SwiftUI

extension QuizQuestionViewController {

    func quizThemeAccentColor(for appearance: AppAppearance) -> UIColor {
        QuizThemeAccentStyle.accentColor(themeID: presenter?.themeID, appearance: appearance)
    }

    func fitContentFonts() {
        guard !view.bounds.isEmpty, !isFittingContentFonts else { return }
        isFittingContentFonts = true
        defer { isFittingContentFonts = false }

        for spacing in adaptiveSpacingConstraints {
            spacing.constraint.constant = usesCompactLayout ? spacing.compact : spacing.regular
        }
        answersStackView.spacing = usesCompactLayout ? 8 : Layout.answersStackSpacing
        view.layoutIfNeeded()

        for pass in 0..<Typography.maximumFontLayoutPasses {
            questionCardView?.layoutIfNeeded()
            answersStackView?.layoutIfNeeded()

            let answerLayoutChanged = fitAnswerFonts()
            let questionFontChanged = fitQuestionFont()

            answerButtons.forEach {
                $0.setNeedsLayout()
                $0.layoutIfNeeded()
            }

            let requiresAnotherPass = pass == 0 || questionFontChanged || answerLayoutChanged
            guard requiresAnotherPass else { break }
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    func layoutContentIfPossible() {
        view.setNeedsLayout()
        guard !view.bounds.isEmpty else { return }
        view.layoutIfNeeded()
    }

    @discardableResult
    func fitQuestionFont() -> Bool {
        let baseFont = currentAppearance().typography.font(
            size: Typography.questionFontSize,
            weight: .bold,
            compatibleWith: view.traitCollection
        )
        let contentWidth = questionLabel.bounds.width
        guard contentWidth > .zero else { return false }

        let text = questionLabel.text ?? ""
        let fittedPointSize = usesScrollableQuestionBody ? baseFont.pointSize : fontFitter.fittedPointSize(
            for: text,
            baseFont: baseFont,
            minimumScaleFactor: Typography.questionMinimumScaleFactor,
            contentWidth: contentWidth,
            targetContentHeight: max(1, availableQuestionHeight),
            requiresFit: true
        )
        questionLabel.preferredMaxLayoutWidth = contentWidth

        let fittedFont = baseFont.withSize(fittedPointSize)
        guard questionLabel.font.fontName != fittedFont.fontName
            || abs(questionLabel.font.pointSize - fittedFont.pointSize) > Typography.fontSizeComparisonTolerance
        else { return false }

        questionLabel.font = fittedFont
        questionLabel.invalidateIntrinsicContentSize()
        questionLabel.setNeedsLayout()
        return true
    }

    @discardableResult
    func fitAnswerFonts() -> Bool {
        let baseFont = currentAppearance().typography.font(
            size: Typography.answerButtonFontSize,
            weight: .semibold,
            compatibleWith: view.traitCollection
        )
        let targetContentHeight = minimumAnswerHeight - (Layout.answerContentVerticalInset * 2)
        let maximumHeight = maximumAnswerHeight
        var requiresLayout = false

        for (index, button) in answerButtons.enumerated() {
            guard let titleLabel = button.titleLabel else { continue }
            let text = button.title(for: .normal) ?? ""
            let contentWidth = button.bounds.width - (Layout.answerContentHorizontalInset * 2)

            guard !text.isEmpty, contentWidth > .zero else {
                if applyAnswerFont(baseFont, to: button) {
                    requiresLayout = true
                }
                if answerHeightConstraints.indices.contains(index),
                   abs(answerHeightConstraints[index].constant - minimumAnswerHeight) > Typography.fontSizeComparisonTolerance {
                    answerHeightConstraints[index].constant = minimumAnswerHeight
                    requiresLayout = true
                }
                continue
            }

            var fittedPointSize = usesScrollableQuestionBody ? baseFont.pointSize : fontFitter.fittedPointSize(
                for: text,
                baseFont: baseFont,
                minimumScaleFactor: Typography.answerMinimumScaleFactor,
                contentWidth: contentWidth,
                targetContentHeight: targetContentHeight
            )

            let maximumContentHeight = maximumHeight - Layout.answerContentVerticalInset * 2
            if !usesScrollableQuestionBody, fontFitter.height(of: text, font: baseFont.withSize(fittedPointSize), contentWidth: contentWidth) > maximumContentHeight {
                fittedPointSize = fontFitter.fittedPointSize(
                    for: text,
                    baseFont: baseFont,
                    minimumScaleFactor: Typography.answerMinimumScaleFactor,
                    contentWidth: contentWidth,
                    targetContentHeight: maximumContentHeight,
                    requiresFit: true
                )
            }

            let fittedFont = baseFont.withSize(fittedPointSize)
            if applyAnswerFont(fittedFont, to: button) {
                requiresLayout = true
            }
            titleLabel.preferredMaxLayoutWidth = contentWidth

            let requiredHeight = max(
                minimumAnswerHeight,
                fontFitter.height(of: text, font: fittedFont, contentWidth: contentWidth)
                    + (Layout.answerContentVerticalInset * 2)
            )
            if answerHeightConstraints.indices.contains(index),
               abs(answerHeightConstraints[index].constant - requiredHeight) > Typography.fontSizeComparisonTolerance {
                answerHeightConstraints[index].constant = requiredHeight
                requiresLayout = true
            }
        }

        if requiresLayout {
            questionCardView?.setNeedsLayout()
            cardContainerView?.setNeedsLayout()
            view.setNeedsLayout()
        }
        return requiresLayout
    }

    var usesScrollableQuestionBody: Bool {
        if view.safeAreaLayoutGuide.layoutFrame.height < 600
            || traitCollection.preferredContentSizeCategory.isAccessibilityCategory { return true }
        let typography = currentAppearance().typography
        let questionFont = typography.font(size: Typography.questionFontSize, weight: .bold, compatibleWith: traitCollection)
        let answerFont = typography.font(size: Typography.answerButtonFontSize, weight: .semibold, compatibleWith: traitCollection)
        let questionHeight = fontFitter.height(of: questionLabel.text ?? "", font: questionFont.withSize(questionFont.pointSize * Typography.questionMinimumScaleFactor), contentWidth: max(1, questionLabel.bounds.width))
        let answerHeight = answerButtons.reduce(CGFloat.zero) { height, button in
            height + max(minimumAnswerHeight, fontFitter.height(of: button.title(for: .normal) ?? "", font: answerFont.withSize(answerFont.pointSize * Typography.answerMinimumScaleFactor), contentWidth: max(1, button.bounds.width - Layout.answerContentHorizontalInset * 2)) + Layout.answerContentVerticalInset * 2)
        }
        return questionHeight + answerHeight > questionContentHeight
    }

    private var availableQuestionHeight: CGFloat {
        questionContentHeight
            - answerHeightConstraints.reduce(0) { $0 + $1.constant }
    }

    private var usesCompactLayout: Bool { view.bounds.height <= 667 }

    private var minimumAnswerHeight: CGFloat {
        usesCompactLayout ? 44 : Layout.answerMinimumHeight
    }

    /// Space shared by the question and answer buttons, excluding all chrome.
    private var questionContentHeight: CGFloat {
        questionCardView.bounds.height
            - (Layout.timerTopInset + (Layout.timerContainerHeight + Layout.timerBarHeight) / 2)
            - Layout.questionSurroundingCompactSpacing * 2
            - Layout.answersBottomInset
            - answersStackView.spacing * CGFloat(max(0, answerButtons.count - 1))
    }

    private var maximumAnswerHeight: CGFloat {
        let font = currentAppearance().typography.font(
            size: Typography.questionFontSize,
            weight: .bold,
            compatibleWith: view.traitCollection
        )
        let preferredQuestionHeight = fontFitter.height(
            of: questionLabel.text ?? "",
            font: font.withSize(font.pointSize * Typography.questionMinimumScaleFactor),
            contentWidth: max(1, questionLabel.bounds.width)
        )
        let count = CGFloat(answerButtons.count)
        let reservedQuestionHeight = min(
            preferredQuestionHeight,
            max(0, questionContentHeight - count * minimumAnswerHeight)
        )
        return max(minimumAnswerHeight, floor((questionContentHeight - reservedQuestionHeight) / count))
    }

    @discardableResult
    func applyAnswerFont(_ font: UIFont, to button: UIButton) -> Bool {
        guard let titleLabel = button.titleLabel else { return false }
        if titleLabel.font.fontName != font.fontName
            || abs(titleLabel.font.pointSize - font.pointSize) > Typography.fontSizeComparisonTolerance {
            titleLabel.font = font
            titleLabel.invalidateIntrinsicContentSize()
            button.invalidateIntrinsicContentSize()
            button.setNeedsLayout()
            return true
        }
        return false
    }
    
    func showResults(_ result: QuizResultState) {
        fadeQuestionChromeForResultTransition()
        router?.showResult(result)
    }

    func fadeQuestionChromeForResultTransition() {
        let changes = {
            self.questionChromeViews.forEach { $0.alpha = 0 }
        }

        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }

        UIView.animate(
            withDuration: QuizCardSlideTransition.presentationDuration,
            delay: 0,
            options: QuizCardSlideTransition.options,
            animations: changes
        )
    }
}
