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

        /// Maximum lines to display before truncation.
        /// With the height cap (maxCodeViewHeight = 500pt), tall code blocks
        /// scroll internally. But the LTXLabel still needs a CALayer for the
        /// full text height. 150 lines × ~18pt × 3x ≈ 8,100px → ~13MB
        /// backing store (vs. 400 lines = ~26,400px → ~117MB).
        /// The full content is preserved in `content` for copy/preview.
        private static let maxDisplayLines = 150

        var content: String = "" {
            didSet {
                guard oldValue != content else { return }
                // Truncate very long code to avoid Metal texture limit crash.
                // The full content is still available via copy button.
                let displayContent = Self.truncateIfNeeded(content)
                textView.attributedText = highlightMap.apply(to: displayContent, with: theme)
                lineNumberView.updateForContent(displayContent)
                updateLineNumberView()
                triggerAsyncHighlight()
            }
        }

        /// Truncates content to maxDisplayLines to stay within GPU texture limits.
        /// Full content is preserved in `content` for copy/export.
        private static func truncateIfNeeded(_ text: String) -> String {
            let lines = text.components(separatedBy: "\n")
            guard lines.count > maxDisplayLines else { return text }
            let truncated = lines.prefix(maxDisplayLines).joined(separator: "\n")
            let remaining = lines.count - maxDisplayLines
            return truncated + "\n\n// ··· \(remaining) more lines ···"
        }

        // MARK: CONTENT -

        /// Tracks the current async highlight task so we can cancel stale ones
        private var highlightTask: Task<Void, Never>?

        /// Triggers async syntax highlighting via HighlightSwift.
        /// Code renders immediately as plain monospaced text, then colors
        /// appear when highlighting completes.
        ///
        /// **Debounced**: Waits 300ms after the last content change before
        /// triggering. During streaming, content changes every ~50ms — each
        /// change cancels the previous timer, so highlighting only runs once
        /// streaming stops and content stabilizes. This is intentional:
        /// MarkdownTextView re-creates CodeView instances on every update,
        /// so mid-stream highlighting would cause colored→plain→colored flicker.
        private func triggerAsyncHighlight() {
            highlightTask?.cancel()
            let capturedContent = content
            let displayContent = Self.truncateIfNeeded(capturedContent)
            let capturedLanguage = language
            let capturedTheme = theme
            highlightTask = Task { [weak self] in
                // Debounce: wait 300ms for content to stabilize
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }

                let map = await CodeHighlighter.current.highlightAsync(
                    content: displayContent,
                    language: capturedLanguage,
                    theme: capturedTheme
                )
                guard !Task.isCancelled, let self,
                      self.content == capturedContent else { return }
                await MainActor.run {
                    self.highlightMap = map
                    self.textView.attributedText = map.apply(to: displayContent, with: capturedTheme)
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

            // Use truncated content's line count (matches what's displayed),
            // not full content which may have hundreds more lines
            let displayContent = Self.truncateIfNeeded(content)
            let lineCount = max(displayContent.components(separatedBy: .newlines).count, 1)
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
