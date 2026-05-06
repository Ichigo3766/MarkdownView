//
//  MarkdownView+RepresentableBase.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import MarkdownParser
import SwiftUI

protocol MarkdownViewRepresentableBase {
    var contentSource: MarkdownView.ContentSource { get }
    var theme: MarkdownTheme { get }
    /// When true, this view is inside an actively-streaming message.
    /// Used to select the throttled update path and stabilize height.
    var codeBlockAutoScroll: Bool { get }
    /// When true, the built-in code block header bar is hidden for all code blocks.
    var codeBlockBarHidden: Bool { get }
    var width: CGFloat { get }
    var heightBinding: Binding<CGFloat> { get }
}

extension MarkdownViewRepresentableBase {
    // Default implementation so AppKit conformers don't need to declare this.
    var codeBlockBarHidden: Bool { false }

    func createMarkdownTextView() -> MarkdownTextView {
        let view = MarkdownTextView()
        view.theme = theme
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        #if canImport(UIKit)
        view.linkHandler = { payload, _, _ in
            let url: URL?
            switch payload {
            case .url(let u): url = u
            case .string(let s): url = URL(string: s)
            }
            if let url {
                NotificationCenter.default.post(
                    name: .markdownLinkTapped,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
        view.codePreviewHandler = { language, attributedString in
            let code = attributedString.string
            NotificationCenter.default.post(
                name: .markdownCodePreview,
                object: nil,
                userInfo: ["code": code, "language": language ?? ""]
            )
        }
        #endif
        return view
    }

    func updateMarkdownTextView(_ view: MarkdownTextView, coordinator: MarkdownViewCoordinator) {
        let isStreaming = codeBlockAutoScroll

        switch contentSource {
        case let .text(text):
            let textChanged = coordinator.lastText != text
            let themeChanged = coordinator.lastTheme != theme

            guard textChanged || themeChanged else {
                // Nothing changed — still update height in case layout pass was skipped.
                #if canImport(UIKit)
                view.setCodeBlockAutoScroll(isStreaming)
                view.setCodeBlockBarHidden(codeBlockBarHidden)
                #endif
                updateMeasuredHeight(for: view, coordinator: coordinator, isStreaming: isStreaming)
                return
            }

            if isStreaming {
                // ── Streaming: parse on background thread ─────────────────────
                // Cancel any in-flight parse from the previous tick so we never
                // pile up N parse tasks. Only the latest text wins.
                coordinator.parseTask?.cancel()

                // Capture everything the background work needs — no coordinator
                // or view captures allowed off main thread.
                let capturedText = text
                let capturedTheme = theme
                let incrementalParser = coordinator.incrementalParser

                // Update lastText immediately so the guard above fires correctly
                // on the *next* SwiftUI update tick even if the Task hasn't finished.
                coordinator.lastText = text
                coordinator.lastTheme = theme

                coordinator.parseTask = Task.detached(priority: .userInitiated) { [weak coordinator] in
                    guard !Task.isCancelled else { return }
                    // IncrementalStreamingParser is a final class with value-type
                    // internal state; all mutations happen here off main thread.
                    let parsed = incrementalParser.parse(capturedText, theme: capturedTheme)
                    guard !Task.isCancelled else { return }

                    await MainActor.run { [weak coordinator] in
                        guard let coordinator else { return }
                        view.theme = capturedTheme
                        view.setMarkdownManually(parsed)
                        view.invalidateIntrinsicContentSize()
                        coordinator.lastHeightMeasureTime = 0
                        #if canImport(UIKit)
                        view.setCodeBlockAutoScroll(true)
                        view.setCodeBlockBarHidden(codeBlockBarHidden)
                        #endif
                        updateMeasuredHeight(for: view, coordinator: coordinator, isStreaming: true)
                    }
                }
                // Return immediately — the Task delivers the result asynchronously.
                return

            } else {
                // ── Non-streaming: full parse, also off main thread ────────────
                coordinator.parseTask?.cancel()
                coordinator.incrementalParser.reset()

                let capturedText = text
                let capturedTheme = theme

                coordinator.lastText = text
                coordinator.lastTheme = theme

                coordinator.parseTask = Task.detached(priority: .userInitiated) { [weak coordinator] in
                    guard !Task.isCancelled else { return }
                    let parser = MarkdownParser()
                    let result = parser.parse(capturedText)
                    let preprocessed = MarkdownTextView.PreprocessedContent(parserResult: result, theme: capturedTheme)
                    guard !Task.isCancelled else { return }

                    await MainActor.run { [weak coordinator] in
                        guard let coordinator else { return }
                        view.theme = capturedTheme
                        view.setMarkdownManually(preprocessed)
                        view.invalidateIntrinsicContentSize()
                        coordinator.lastTheme = capturedTheme
                        coordinator.lastHeightMeasureTime = 0
                        #if canImport(UIKit)
                        view.setCodeBlockAutoScroll(false)
                        view.setCodeBlockBarHidden(codeBlockBarHidden)
                        #endif
                        updateMeasuredHeight(for: view, coordinator: coordinator, isStreaming: false)
                    }
                }
                return
            }

        case let .preprocessed(preprocessedContent):
            let needsUpdate = coordinator.lastPreprocessedContent !== preprocessedContent
                || coordinator.lastTheme != theme
            if needsUpdate {
                coordinator.lastText = ""
                coordinator.lastPreprocessedContent = preprocessedContent
                coordinator.lastTheme = theme
                view.theme = theme
                view.setMarkdownManually(preprocessedContent)
                view.invalidateIntrinsicContentSize()
                coordinator.lastHeightMeasureTime = 0
            }
            #if canImport(UIKit)
            view.setCodeBlockAutoScroll(isStreaming)
            view.setCodeBlockBarHidden(codeBlockBarHidden)
            #endif
            updateMeasuredHeight(for: view, coordinator: coordinator, isStreaming: isStreaming)
        }
    }

    func updateMeasuredHeight(
        for view: MarkdownTextView,
        coordinator: MarkdownViewCoordinator,
        isStreaming: Bool = false
    ) {
        guard width.isFinite, width > 0 else { return }

        // During streaming, calling `boundingSize(for:)` on every token causes
        // a full O(n) CoreText layout pass on the entire growing attributed string.
        // Throttle to at most once per `heightThrottleInterval` seconds while
        // streaming; always measure immediately when streaming ends or content changes.
        if isStreaming {
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - coordinator.lastHeightMeasureTime
            guard elapsed >= MarkdownViewCoordinator.heightThrottleInterval else { return }
            coordinator.lastHeightMeasureTime = now
        }

        let size = view.boundingSize(for: width)
        let height = ceil(size.height)
        let current = heightBinding.wrappedValue

        guard abs(height - current) > 0.5 else { return }
        // Wrap in a nil-animation transaction so SwiftUI never animates the
        // height change. Without this, advancing the paragraph-freeze boundary
        // causes a bounce: the frozen view grows (async height +) while the
        // live tail shrinks (async height -) and the two deferred updates
        // play as an animated spring rather than an instant no-op.
        DispatchQueue.main.async {
            var tx = Transaction(animation: nil)
            tx.disablesAnimations = true
            withTransaction(tx) {
                self.heightBinding.wrappedValue = height
            }
        }
    }
}
