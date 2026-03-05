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

    /// The currently in-flight background parse work item.
    /// Cancelled when new content arrives to prevent queue pile-up.
    var pendingParseWork: DispatchWorkItem?

    /// Set to true when the coordinator is being torn down.
    var isCancelled: Bool = false

    deinit {
        isCancelled = true
        pendingParseWork?.cancel()
        pendingParseWork = nil
    }
}
