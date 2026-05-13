//
//  MarkdownView+View.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import MarkdownParser
import SwiftUI

public struct MarkdownView: View {
    public typealias PreprocessedContent = MarkdownTextView.PreprocessedContent

    enum ContentSource {
        case text(String)
        case preprocessed(PreprocessedContent)
    }

    let contentSource: ContentSource
    public var theme: MarkdownTheme
    /// When true, all code blocks inside this MarkdownView auto-scroll to their bottom.
    /// Set true during streaming, false when streaming ends.
    public var codeBlockAutoScroll: Bool = false
    /// When true, the built-in header bar of every code block is hidden.
    /// Use this when a parent view provides its own header (e.g. PythonCodeBlockView).
    public var codeBlockBarHidden: Bool = false

    public init(_ text: String, theme: MarkdownTheme = .default) {
        contentSource = .text(text)
        self.theme = theme
    }

    public init(_ preprocessedContent: PreprocessedContent, theme: MarkdownTheme = .default) {
        contentSource = .preprocessed(preprocessedContent)
        self.theme = theme
    }

    /// Fluent setter for codeBlockAutoScroll.
    public func codeAutoScroll(_ enabled: Bool) -> MarkdownView {
        var copy = self
        copy.codeBlockAutoScroll = enabled
        return copy
    }

    /// Fluent setter for codeBlockBarHidden.
    /// When `hidden` is true, the built-in language/copy/preview bar inside every
    /// code block is suppressed so a container view can render its own header.
    public func codeBarHidden(_ hidden: Bool) -> MarkdownView {
        var copy = self
        copy.codeBlockBarHidden = hidden
        return copy
    }

    public var body: some View {
        // Use sizeThatFits on the representable — the UIViewRepresentable protocol method
        // is called synchronously during SwiftUI's layout pass and returns the correct
        // height without any @State feedback loop.
        //
        // The old GeometryReader + @State measuredHeight + DispatchQueue.main.async write
        // pattern created an AttributeGraph cycle: writing @State from updateUIView caused
        // SwiftUI to re-evaluate body mid-layout, which re-entered updateUIView, which
        // dispatched another async write — spamming "AttributeGraph: cycle detected" on
        // every prompt send and at every animation interpolation tick (60fps × N messages).
        //
        // With sizeThatFits SwiftUI reads size directly from the representable; when async
        // parsing completes, invalidateIntrinsicContentSize() on the MarkdownTextView tells
        // SwiftUI to re-measure — no @State, no cycle.
        MarkdownViewRepresentable(
            contentSource: contentSource,
            theme: theme,
            codeBlockAutoScroll: codeBlockAutoScroll,
            codeBlockBarHidden: codeBlockBarHidden
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
