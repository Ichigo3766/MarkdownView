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
            let needsUpdate = coordinator.lastText != text
                || coordinator.lastTheme != theme
            guard needsUpdate else {
                updateMeasuredHeight(for: view)
                return
            }

            coordinator.lastText = text
            coordinator.lastPreprocessedContent = nil

            if coordinator.lastTheme != theme {
                view.theme = theme
                coordinator.lastTheme = theme
            }

            // Cancel any previous in-flight parse work item to prevent
            // queue pile-up during streaming (memory leak fix).
            coordinator.pendingParseWork?.cancel()

            let currentTheme = theme
            let capturedText = text
            let workItem = DispatchWorkItem { [weak coordinator] in
                guard let coordinator, !coordinator.isCancelled else { return }

                let parser = MarkdownParser()
                let result = parser.parse(capturedText)

                guard !coordinator.isCancelled else { return }

                let content = MarkdownTextView.PreprocessedContent(
                    parserResult: result, theme: currentTheme)

                DispatchQueue.main.async {
                    // Only deliver if content hasn't changed since we started parsing
                    guard coordinator.lastText == capturedText else { return }
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
