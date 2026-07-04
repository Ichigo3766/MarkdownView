//
//  MarkdownView+RepresentableBase.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import MarkdownParser
import SwiftUI
import UIKit

protocol MarkdownViewRepresentableBase {
    var contentSource: MarkdownView.ContentSource { get }
    var theme: MarkdownTheme { get }
    var codeBlockAutoScroll: Bool { get }
    var codeBlockBarHidden: Bool { get }
    var citationSources: [Int: URL] { get }
}

extension MarkdownViewRepresentableBase {
    func createMarkdownTextView() -> MarkdownTextView {
        let view = MarkdownTextView()
        view.theme = theme
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        return view
    }

    func updateMarkdownTextView(_ view: MarkdownTextView, coordinator: MarkdownViewCoordinator) {
        let isStreaming = codeBlockAutoScroll
        defer { coordinator.lastStreamingState = isStreaming }

        switch contentSource {
        case let .text(text):
            let textChanged = coordinator.lastText != text
            let themeChanged = coordinator.lastTheme != theme
            let wasStreaming = coordinator.lastStreamingState
            let streamingJustEnded = wasStreaming && !isStreaming

            // ── Streaming → idle transition ────────────────────────────────
            // Instead of a full re-parse (which replaces the entire attributed
            // string and jumps scroll position), use the incremental parser's
            // finalize() to settle only the unsettled tail blocks in-place.
            // The block-level diff in updateTextExecute() ensures only the
            // changed blocks are re-rendered — stable content stays untouched.
            if streamingJustEnded {
                coordinator.parseTask?.cancel()

                let capturedText = coordinator.lastText  // final streamed text
                let capturedTheme = theme
                let capturedBarHidden = codeBlockBarHidden
                let incrementalParser = coordinator.incrementalParser

                coordinator.lastText = capturedText
                coordinator.lastTheme = capturedTheme

                coordinator.parseTask = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    // finalize() settles the whole text with minTailLength=0,
                    // rendering citations/math in the final paragraph without
                    // rebuilding the whole attributed string from scratch.
                    let finalized = incrementalParser.finalize(capturedText, theme: capturedTheme)
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        view.theme = capturedTheme
                        view.setMarkdownManually(finalized)
                        view.invalidateIntrinsicContentSize()
                        view.setCodeBlockAutoScroll(false)
                        view.setCodeBlockBarHidden(capturedBarHidden)
                    }
                }

                view.setCodeBlockAutoScroll(false)
                view.setCodeBlockBarHidden(codeBlockBarHidden)
                return
            }

            guard textChanged || themeChanged else {
                view.setCodeBlockAutoScroll(isStreaming)
                view.setCodeBlockBarHidden(codeBlockBarHidden)
                return
            }

            if isStreaming {
                // ── Streaming: parse on background thread ─────────────────────
                coordinator.parseTask?.cancel()

                let capturedText = text
                let capturedTheme = theme
                let capturedBarHidden = codeBlockBarHidden
                let incrementalParser = coordinator.incrementalParser

                coordinator.lastText = text
                coordinator.lastTheme = theme

                coordinator.parseTask = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    let parsed = incrementalParser.parse(capturedText, theme: capturedTheme)
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        view.theme = capturedTheme
                        view.setMarkdownManually(parsed)
                        view.invalidateIntrinsicContentSize()
                        view.setCodeBlockAutoScroll(true)
                        view.setCodeBlockBarHidden(capturedBarHidden)
                    }
                }
                return

            } else {
                // ── Non-streaming: full parse, also off main thread ────────────
                coordinator.parseTask?.cancel()
                coordinator.incrementalParser.reset()

                let capturedText = text
                let capturedTheme = theme
                let capturedCodeBlockBarHidden = codeBlockBarHidden

                coordinator.lastText = text
                coordinator.lastTheme = theme

                coordinator.parseTask = Task.detached(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    let parser = MarkdownParser()
                    let result = parser.parse(capturedText)
                    let preprocessed = MarkdownTextView.PreprocessedContent(parserResultNoMath: result)
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        view.theme = capturedTheme
                        view.setMarkdownManually(preprocessed)
                        view.invalidateIntrinsicContentSize()
                        view.setCodeBlockAutoScroll(false)
                        view.setCodeBlockBarHidden(capturedCodeBlockBarHidden)
                    }

                    // Pass 2: render math off-thread, then refresh the view.
                    // IMPORTANT: we must clear the block-level render cache before
                    // calling setMarkdownManually again, otherwise updateTextExecute()
                    // sees identical blocks and returns early without redrawing the
                    // math images that were just rendered into preprocessed.rendered.
                    guard !Task.isCancelled else { return }
                    preprocessed.renderMathAsync(theme: capturedTheme) { @MainActor in
                        view.cachedBlockSegments.removeAll()
                        view.setMarkdownManually(preprocessed)
                        view.invalidateIntrinsicContentSize()
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
            }
            view.setCodeBlockAutoScroll(isStreaming)
            view.setCodeBlockBarHidden(codeBlockBarHidden)
        }
    }
}
