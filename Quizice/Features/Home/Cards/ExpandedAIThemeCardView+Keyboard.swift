import UIKit

extension ExpandedAIThemeCardView {
    func configureKeyboardAccessory() {
        let toolbar = UIToolbar()
        let flexibleSpace = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )
        let doneButton = UIBarButtonItem(
            title: L10n.Settings.done,
            style: .done,
            target: self,
            action: #selector(keyboardDoneTapped)
        )
        doneButton.accessibilityIdentifier = AccessibilityID.keyboardDoneButton
        toolbar.items = [flexibleSpace, doneButton]
        toolbar.sizeToFit()
        promptTextView.inputAccessoryView = toolbar
    }

    func configureKeyboardObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func updateAdaptiveSelectorLayout() {
        let usesAccessibilityLayout = traitCollection.preferredContentSizeCategory
            .isAccessibilityCategory
        difficultyStack.axis = usesAccessibilityLayout ? .vertical : .horizontal
        difficultyStack.distribution = usesAccessibilityLayout ? .fill : .fillEqually
        difficultyButtons.forEach { button in
            button.titleLabel?.numberOfLines = usesAccessibilityLayout ? 0 : 1
            button.titleLabel?.adjustsFontSizeToFitWidth = !usesAccessibilityLayout
            button.titleLabel?.textAlignment = .center
        }
    }

    func updateKeyboardInsets(
        overlap: CGFloat,
        duration: TimeInterval,
        options: UIView.AnimationOptions
    ) {
        let bottomInset = max(
            Layout.scrollBottomInset,
            overlap > 0 ? overlap + Layout.promptTextInset : 0
        )
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.frontScrollView.contentInset.bottom = bottomInset
            self.frontScrollView.verticalScrollIndicatorInsets.bottom = bottomInset
            self.layoutIfNeeded()
            self.scrollPromptCaretIntoView()
        }
    }

    func scrollPromptCaretIntoView() {
        guard
            face == .front,
            promptTextView.isFirstResponder
        else { return }

        let promptRect = promptContainerView.convert(promptContainerView.bounds, to: frontScrollView)
            .insetBy(dx: -Layout.promptTextInset, dy: -Layout.promptTextInset)
        let visibleHeight = max(
            frontScrollView.bounds.height
                - frontScrollView.adjustedContentInset.top
                - frontScrollView.adjustedContentInset.bottom,
            0
        )
        if promptRect.height <= visibleHeight {
            frontScrollView.scrollRectToVisible(promptRect, animated: false)
            return
        }

        guard let selectedRange = promptTextView.selectedTextRange else { return }
        var caretRect = promptTextView.caretRect(for: selectedRange.end)
        caretRect = promptTextView.convert(caretRect, to: frontScrollView)
        caretRect = caretRect.insetBy(dx: -Layout.promptTextInset, dy: -Layout.promptTextInset)
        frontScrollView.scrollRectToVisible(caretRect, animated: false)
    }

    @objc func keyboardDoneTapped() {
        resignPrompt()
    }

    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            face == .front,
            promptTextView.isFirstResponder,
            let window,
            let userInfo = notification.userInfo,
            let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let frameInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let curveRawValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
        updateKeyboardFrameInWindow(frameInWindow, duration: duration, options: options)
    }

    func updateKeyboardFrameInWindow(
        _ frame: CGRect?, duration: TimeInterval, options: UIView.AnimationOptions
    ) {
        onKeyboardFrameChange?(frame, duration, options)
        let overlap: CGFloat
        if let frame, let window {
            overlap = bounds.intersection(convert(frame, from: window)).height
        } else {
            overlap = 0
        }
        updateKeyboardInsets(overlap: overlap, duration: duration, options: options)
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        let userInfo = notification.userInfo
        let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let curveRawValue = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
        updateKeyboardFrameInWindow(nil, duration: duration, options: options)
    }
}
