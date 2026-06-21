//
//  MarkdownTextView+Private.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import Combine
import Foundation
import Litext

extension MarkdownTextView {
    func resetCombine() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func setupCombine() {
        resetCombine()
        contentSubject
            .sink { [weak self] content in self?.use(content) }
            .store(in: &cancellables)
    }

    func use(_ content: PreprocessedContent) {
        assert(Thread.isMainThread)

        // When content is empty (reset case), clear the block-level cache AND the
        // persistent attributed string so the next real document starts clean.
        if content.blocks.isEmpty {
            cachedBlockSegments.removeAll()
            cachedAttributedString = .init()
        }

        document = content
        // due to a bug in model gemini-flash
        // there might be a large of unknown empty whitespace inside the table
        // thus we hereby call the autoreleasepool to avoid large memory consumption
        autoreleasepool { updateTextExecute() }

        // MEMORY FIX: After updateTextExecute() bakes the AST and math images
        // into the NSAttributedString, the PreprocessedContent's heavyweight data
        // is no longer needed. Replace with an empty instance to free that memory.
        document = PreprocessedContent()

        // Do NOT call layoutIfNeeded() here.
        // updateTextExecute() already called setNeedsLayout(), which schedules
        // layout for the next run-loop pass. The run-loop will batch and coalesce
        // layout passes automatically.
    }
}
