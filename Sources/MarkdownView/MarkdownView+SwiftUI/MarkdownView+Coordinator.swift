//
//  MarkdownView+Coordinator.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import Foundation

final class MarkdownViewCoordinator {
    var lastText: String = ""
    /// Fast O(1) hash guard — avoids full string comparison on every SwiftUI update.
    var lastTextHash: Int = 0
    var lastPreprocessedContent: MarkdownTextView.PreprocessedContent?
    var lastTheme: MarkdownTheme = .default
}
