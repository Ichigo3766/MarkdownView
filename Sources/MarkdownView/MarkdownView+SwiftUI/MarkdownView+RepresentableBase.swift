//
//  MarkdownView+RepresentableBase.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import MarkdownParser
import SwiftUI

/// Background queue for markdown parsing — pure computation, thread-safe.
/// Moving parsing off the main thread prevents blocking UI during streaming.
private let markdownParseQueue = DispatchQueue(
    label: "MarkdownView.ParseQueue",
    qos: .userInteractive
)

protocol MarkdownViewRepresentableBase {
    var contentSource: MarkdownView.ContentSource { get }
    var theme: MarkdownTheme { get }
    var width: CGFloat { get }
    var heightBinding: Binding<CGFloat> { get }
}

extension MarkdownViewRepresentableBase {
    func createMarkdownTextView() -> MarkdownTextView {
        let view = MarkdownTextView()
        view.theme = theme
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateMarkdownTextView(_ view: MarkdownTextView, coordinator: MarkdownViewCoordinator) {
        switch contentSource {
        case let .text(text):
            // Phase 1: Fast content hash guard — skip entirely if unchanged
            let textHash = text.hashValue
            let themeChanged = coordinator.lastTheme != theme
            guard textHash != coordinator.lastTextHash || themeChanged else {
                // Content identical — just update height (width may have changed)
                updateMeasuredHeight(for: view)
                return
            }

            coordinator.lastText = text
            coordinator.lastTextHash = textHash
            coordinator.lastPreprocessedContent = nil

            if themeChanged {
                view.theme = theme
                coordinator.lastTheme = theme
            }

            // Phase 2: Parse markdown on background thread, then deliver
            // to the throttled Combine pipeline on main thread.
            // MarkdownParser is pure computation — no UIKit dependencies.
            let currentTheme = theme
            markdownParseQueue.async {
                let parser = MarkdownParser()
                let result = parser.parse(text)
                let content = MarkdownTextView.PreprocessedContent(
                    parserResult: result, theme: currentTheme)
                DispatchQueue.main.async {
                    // Phase 1: Use setMarkdown() (throttled Combine pipeline)
                    // instead of setMarkdownManually() (bypasses throttle).
                    // This engages the built-in 20fps throttle so even if
                    // SwiftUI calls updateView 50x/sec, only ~20 renders execute.
                    view.setMarkdown(content)
                    view.invalidateIntrinsicContentSize()
                    self.updateMeasuredHeight(for: view)
                }
            }

        case let .preprocessed(preprocessedContent):
            let needsUpdate = coordinator.lastPreprocessedContent !== preprocessedContent
                || coordinator.lastTheme != theme
            if needsUpdate {
                coordinator.lastText = ""
                coordinator.lastTextHash = 0
                coordinator.lastPreprocessedContent = preprocessedContent
                view.theme = theme
                // Pre-processed content is already parsed — use throttled path
                view.setMarkdown(preprocessedContent)
                view.invalidateIntrinsicContentSize()
                coordinator.lastTheme = theme
            }
            updateMeasuredHeight(for: view)
        }
    }

    func updateMeasuredHeight(for view: MarkdownTextView) {
        guard width.isFinite, width > 0 else { return }
        let size = view.boundingSize(for: width)
        let height = ceil(size.height)
        guard abs(height - heightBinding.wrappedValue) > 0.5 else { return }
        DispatchQueue.main.async {
            self.heightBinding.wrappedValue = height
        }
    }
}
