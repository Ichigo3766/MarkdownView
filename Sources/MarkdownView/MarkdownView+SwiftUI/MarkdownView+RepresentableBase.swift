//
//  MarkdownView+RepresentableBase.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import MarkdownParser
import SwiftUI

/// Background queue for markdown parsing — pure computation, thread-safe.
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
            // Fast content hash guard — skip entirely if unchanged
            let textHash = text.hashValue
            let themeChanged = coordinator.lastTheme != theme
            guard textHash != coordinator.lastTextHash || themeChanged else {
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

            // CRITICAL FIX: Cancel any previous in-flight parse work item.
            // Without this, every streaming token queues a new full parse
            // on the serial background queue. With 1000-line code blocks,
            // each parse creates ~10MB of PreprocessedContent (AST + 
            // NSAttributedStrings + highlight maps). At 20 tokens/sec with
            // 200ms parse time, the queue grows unboundedly → 3GB+ memory.
            coordinator.pendingParseWork?.cancel()

            let currentTheme = theme
            let workItem = DispatchWorkItem { [weak coordinator] in
                // Check if this work was cancelled before doing expensive work
                guard let coordinator, !coordinator.isCancelled else { return }

                let parser = MarkdownParser()
                let result = parser.parse(text)

                // Check again after parse (may have been cancelled during parse)
                guard !coordinator.isCancelled else { return }

                let content = MarkdownTextView.PreprocessedContent(
                    parserResult: result, theme: currentTheme)

                DispatchQueue.main.async {
                    // Final check — content may have changed while we were parsing
                    guard coordinator.lastTextHash == textHash else { return }
                    view.setMarkdown(content)
                    view.invalidateIntrinsicContentSize()
                    self.updateMeasuredHeight(for: view)
                }
            }

            coordinator.pendingParseWork = workItem
            markdownParseQueue.async(execute: workItem)

        case let .preprocessed(preprocessedContent):
            let needsUpdate = coordinator.lastPreprocessedContent !== preprocessedContent
                || coordinator.lastTheme != theme
            if needsUpdate {
                coordinator.lastText = ""
                coordinator.lastTextHash = 0
                coordinator.lastPreprocessedContent = preprocessedContent
                view.theme = theme
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
