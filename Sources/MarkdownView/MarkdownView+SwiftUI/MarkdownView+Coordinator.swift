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

    // Height-measurement throttle: during streaming we skip the expensive
    // `boundingSize(for:)` call if we measured less than `heightThrottleInterval`
    // seconds ago. This avoids a full O(n) CoreText layout pass on every token.
    var lastHeightMeasureTime: CFAbsoluteTime = 0
    /// Minimum interval between height measurements when streaming (seconds).
    static let heightThrottleInterval: CFAbsoluteTime = 0.15
}
