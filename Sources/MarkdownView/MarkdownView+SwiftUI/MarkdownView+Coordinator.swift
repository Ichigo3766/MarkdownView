//
//  MarkdownView+Coordinator.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import Foundation

final class MarkdownViewCoordinator {
    var lastText: String = ""
    var lastPreprocessedContent: MarkdownTextView.PreprocessedContent?
    var lastTheme: MarkdownTheme = .default

    /// Incremental parser used only during streaming (`codeBlockAutoScroll == true`).
    /// Maintains a cached stable prefix so only the short live tail is re-parsed
    /// each drain tick rather than the full accumulated text.
    let incrementalParser = IncrementalStreamingParser()

    /// Background parse task for the streaming incremental path.
    /// Each new tick cancels the previous task so only the latest content wins.
    /// The parsed `PreprocessedContent` is delivered back on the main actor.
    var parseTask: Task<Void, Never>? = nil
}
