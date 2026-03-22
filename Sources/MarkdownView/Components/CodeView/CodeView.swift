//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Litext

#if canImport(UIKit)
    import UIKit

    final class CodeView: UIView {
        // MARK: - CONTENT

        var theme: MarkdownTheme = .default {
            didSet {
                languageLabel.font = theme.fonts.code
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                updateLineNumberView()
            }
        }

        var language: String = "" {
            didSet {
                languageLabel.text = language.isEmpty ? "</>" : language
            }
        }

        var highlightMap: CodeHighlighter.HighlightMap = .init()

        // MARK: - Auto-Scroll

        /// When true, the code block scrolls to the bottom whenever new content arrives.
        /// Set to false when the user manually scrolls up; the FAB re-enables it.
        var autoScrollEnabled: Bool = false {
            didSet { updateScrollFABVisibility() }
        }

        private lazy var scrollFAB: UIButton = {
            let btn = UIButton(type: .system)
            let img = UIImage(systemName: "arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
            btn.setImage(img, for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = UIColor.systemGray.withAlphaComponent(0.7)
            btn.layer.cornerRadius = 13
            btn.layer.cornerCurve = .continuous
            btn.clipsToBounds = true
            btn.addTarget(self, action: #selector(scrollFABTapped), for: .touchUpInside)
            btn.alpha = 0
            return btn
        }()

        @objc private func scrollFABTapped() {
            autoScrollEnabled = true
            scrollToBottom(animated: true)
        }

        private func scrollToBottom(animated: Bool) {
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            guard maxOffset > 0 else { return }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maxOffset), animated: animated)
        }

        private func updateScrollFABVisibility() {
            let shouldShow = !autoScrollEnabled && scrollView.contentSize.height > scrollView.bounds.height
            UIView.animate(withDuration: 0.2) {
                self.scrollFAB.alpha = shouldShow ? 1 : 0
            }
        }

        // MARK: - Content

        var content: String = "" {
            didSet {
                guard oldValue != content else { return }
                textView.attributedText = highlightMap.apply(to: content, with: theme)
                lineNumberView.updateForContent(content)
                updateLineNumberView()
                triggerAsyncHighlight()
                if autoScrollEnabled {
                    // Defer scroll until after layout pass so contentSize is updated.
                    DispatchQueue.main.async { [weak self] in
                        self?.scrollToBottom(animated: false)
                    }
                }
            }
        }

        // MARK: CONTENT -

        /// Tracks the current async highlight task so we can cancel stale ones
        private var highlightTask: Task<Void, Never>?

        private func triggerAsyncHighlight() {
            highlightTask?.cancel()
            let capturedContent = content
            let capturedLanguage = language
            let capturedTheme = theme
            highlightTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }

                let map = await CodeHighlighter.current.highlightAsync(
                    content: capturedContent,
                    language: capturedLanguage,
                    theme: capturedTheme
                )
                guard !Task.isCancelled, let self,
                      self.content == capturedContent else { return }
                await MainActor.run {
                    self.highlightMap = map
                    self.textView.attributedText = map.apply(to: capturedContent, with: capturedTheme)
                }
            }
        }

        var previewAction: ((String?, NSAttributedString) -> Void)? {
            didSet {
                setNeedsLayout()
            }
        }

        private let callerIdentifier = UUID()
        private var currentTaskIdentifier: UUID?

        lazy var barView: UIView = .init()
        lazy var scrollView: UIScrollView = .init()
        lazy var languageLabel: UILabel = .init()
        lazy var textView: LTXLabel = .init()
        lazy var copyButton: UIButton = .init()
        lazy var previewButton: UIButton = .init()
        lazy var lineNumberView: LineNumberView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            updateLineNumberView()
            scrollView.delegate = self
            addSubview(scrollFAB)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func intrinsicHeight(for content: String, theme: MarkdownTheme = .default) -> CGFloat {
            CodeViewConfiguration.intrinsicHeight(for: content, theme: theme)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            performLayout()
            updateLineNumberView()
            // Keep FAB pinned to bottom-right corner of the code block.
            let fabSize: CGFloat = 26
            let margin: CGFloat = 8
            scrollFAB.frame = CGRect(
                x: bounds.width - fabSize - margin,
                y: bounds.height - fabSize - margin,
                width: fabSize,
                height: fabSize
            )
            bringSubviewToFront(scrollFAB)
            updateScrollFABVisibility()
        }

        override var intrinsicContentSize: CGSize {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = labelSize.height + CodeViewConfiguration.barPadding * 2
            let textSize = textView.intrinsicContentSize
            let lineNumberWidth = lineNumberView.intrinsicContentSize.width

            let naturalHeight = barHeight + textSize.height + CodeViewConfiguration.codePadding * 2
            // Cap total height to prevent massive CALayer backing stores.
            // A 400-line code block at 3x Retina would be ~8,800pt = 26,400px
            // → ~117MB backing store. Capping at 500pt = 1,500px → ~2.5MB.
            // Content beyond the cap scrolls vertically inside the scrollView.
            let cappedHeight = min(naturalHeight, CodeViewConfiguration.maxCodeViewHeight)
            return CGSize(
                width: max(
                    labelSize.width + CodeViewConfiguration.barPadding * 2,
                    lineNumberWidth + textSize.width + CodeViewConfiguration.codePadding * 2
                ),
                height: cappedHeight
            )
        }

        @objc func handleCopy(_: UIButton) {
            UIPasteboard.general.string = content
            #if !os(visionOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }

        @objc func handlePreview(_: UIButton) {
            #if !os(visionOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            // Pass full content (not truncated) for fullscreen preview
            let fullAttr = highlightMap.apply(to: content, with: theme)
            previewAction?(language, fullAttr)
        }

        func updateLineNumberView() {
            let font = theme.fonts.code
            lineNumberView.textColor = theme.colors.body.withAlphaComponent(0.5)

            let lineCount = max(content.components(separatedBy: .newlines).count, 1)
            let textViewContentHeight = textView.intrinsicContentSize.height

            lineNumberView.configure(
                lineCount: lineCount,
                contentHeight: textViewContentHeight,
                font: font,
                textColor: .secondaryLabel
            )

            lineNumberView.padding = UIEdgeInsets(
                top: CodeViewConfiguration.codePadding,
                left: CodeViewConfiguration.lineNumberPadding,
                bottom: CodeViewConfiguration.codePadding,
                right: CodeViewConfiguration.lineNumberPadding
            )
        }
    }

    extension CodeView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            textView.attributedText
        }
    }

    extension CodeView: UIScrollViewDelegate {
        func scrollViewWillBeginDragging(_: UIScrollView) {
            // User grabbed the scroll view — disable auto-scroll and show FAB.
            autoScrollEnabled = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateScrollFABVisibility()
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class CodeView: NSView {
        var theme: MarkdownTheme = .default {
            didSet {
                languageLabel.font = theme.fonts.code
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                updateLineNumberView()
            }
        }

        var language: String = "" {
            didSet {
                languageLabel.stringValue = language.isEmpty ? "</>" : language
            }
        }

        var highlightMap: CodeHighlighter.HighlightMap = .init()

        var content: String = "" {
            didSet {
                guard oldValue != content else { return }
                textView.attributedText = highlightMap.apply(to: content, with: theme)
                lineNumberView.updateForContent(content)
                updateLineNumberView()
            }
        }

        var previewAction: ((String?, NSAttributedString) -> Void)? {
            didSet {
                needsLayout = true
            }
        }

        private let callerIdentifier = UUID()
        private var currentTaskIdentifier: UUID?

        lazy var barView: NSView = .init()
        lazy var scrollView: NSScrollView = {
            let sv = NSScrollView()
            sv.hasVerticalScroller = false
            sv.hasHorizontalScroller = false
            sv.drawsBackground = false
            return sv
        }()

        lazy var languageLabel: NSTextField = {
            let label = NSTextField(labelWithString: "")
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            return label
        }()

        lazy var textView: LTXLabel = .init()
        lazy var copyButton: NSButton = .init(title: "", target: nil, action: nil)
        lazy var previewButton: NSButton = .init(title: "", target: nil, action: nil)
        lazy var lineNumberView: LineNumberView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            updateLineNumberView()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isFlipped: Bool {
            true
        }

        static func intrinsicHeight(for content: String, theme: MarkdownTheme = .default) -> CGFloat {
            CodeViewConfiguration.intrinsicHeight(for: content, theme: theme)
        }

        override func layout() {
            super.layout()
            performLayout()
            updateLineNumberView()
        }

        override var intrinsicContentSize: CGSize {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = labelSize.height + CodeViewConfiguration.barPadding * 2
            let textSize = textView.intrinsicContentSize
            let supposedHeight = Self.intrinsicHeight(for: content, theme: theme)

            let lineNumberWidth = lineNumberView.intrinsicContentSize.width

            return CGSize(
                width: max(
                    labelSize.width + CodeViewConfiguration.barPadding * 2,
                    lineNumberWidth + textSize.width + CodeViewConfiguration.codePadding * 2
                ),
                height: max(
                    barHeight + textSize.height + CodeViewConfiguration.codePadding * 2,
                    supposedHeight
                )
            )
        }

        @objc func handleCopy(_: Any?) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        }

        @objc func handlePreview(_: Any?) {
            previewAction?(language, textView.attributedText)
        }

        func updateLineNumberView() {
            let font = theme.fonts.code
            lineNumberView.textColor = theme.colors.body.withAlphaComponent(0.5)

            let lineCount = max(content.components(separatedBy: .newlines).count, 1)
            let textViewContentHeight = textView.intrinsicContentSize.height

            lineNumberView.configure(
                lineCount: lineCount,
                contentHeight: textViewContentHeight,
                font: font,
                textColor: .secondaryLabelColor
            )

            lineNumberView.padding = NSEdgeInsets(
                top: CodeViewConfiguration.codePadding,
                left: CodeViewConfiguration.lineNumberPadding,
                bottom: CodeViewConfiguration.codePadding,
                right: CodeViewConfiguration.lineNumberPadding
            )
        }
    }

    extension CodeView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            textView.attributedText
        }
    }
#endif
