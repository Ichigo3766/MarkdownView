
//
//  StreamingCodeBlockView.swift
//  MarkdownView
//
//  A lightweight SwiftUI wrapper around CodeView that bypasses MarkdownParser /
//  IncrementalStreamingParser entirely.
//
//  During streaming, every token appended to a code block would cause
//  IncrementalStreamingParser to re-parse the full growing tail (the entire
//  unclosed fence is unsplittable, so it is always the "live tail").  This
//  produces O(n²) cumulative parse work and drives CPU well above 200 % by the
//  time a block reaches ~200 lines.
//
//  StreamingCodeBlockView short-circuits that path: it hands `content` directly
//  to CodeView.content, which uses its own O(delta) incremental append path
//  (appendToLineIndex + applyWindowedText).  No markdown parsing, no CoreText
//  layout of the whole document, no SwiftUI re-measure — just an O(viewport)
//  windowed text update per token.
//
//  Usage:
//    StreamingCodeBlockView(language: "python", content: liveCode, isStreaming: true)
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI view that renders a live-streaming code block directly via `CodeView`.
///
/// - `language`:    The fence language tag (e.g. "python", "swift", "").
/// - `content`:     The current (growing) code string. Updated on every drain tick.
/// - `isStreaming`: Passed through to `CodeView.isStreaming` which controls
///                  auto-scroll and suppresses the final syntax-highlight pass
///                  until streaming ends.
/// - `theme`:       The MarkdownTheme to apply. Defaults to `.default`.
public struct StreamingCodeBlockView: UIViewRepresentable {

    public let language: String
    public let content: String
    public let isStreaming: Bool
    public var theme: MarkdownTheme

    public init(
        language: String,
        content: String,
        isStreaming: Bool,
        theme: MarkdownTheme = .default
    ) {
        self.language = language
        self.content = content
        self.isStreaming = isStreaming
        self.theme = theme
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> CodeView {
        let codeView = CodeView()
        codeView.theme = theme
        codeView.language = language
        codeView.isStreaming = isStreaming
        codeView.content = content
        // Wire the full-screen preview notification so the copy/preview bar works.
        codeView.previewAction = { lang, attrStr in
            NotificationCenter.default.post(
                name: .markdownCodePreview,
                object: nil,
                userInfo: ["code": attrStr.string, "language": lang ?? ""]
            )
        }
        return codeView
    }

    public func updateUIView(_ codeView: CodeView, context: Context) {
        // Theme: only rebuild if changed (avoids unnecessary full resets).
        if codeView.theme != theme {
            codeView.theme = theme
        }
        // Language: only update when changed (drives the language label).
        if codeView.language != language {
            codeView.language = language
        }
        // Streaming flag: CodeView.isStreaming has a guard `guard isStreaming != oldValue`
        // so setting the same value is a no-op.
        if codeView.isStreaming != isStreaming {
            codeView.isStreaming = isStreaming
        }
        // Content: Use utf8.count as a cheap O(1) pre-check before the full O(n)
        // string equality comparison. During streaming, content grows every tick so
        // byte counts will differ — we skip the expensive == in the common case.
        // When counts match (rare during streaming), fall through to == for correctness.
        let oldContent = codeView.content
        if oldContent.utf8.count != content.utf8.count || oldContent != content {
            codeView.content = content
        }
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: CodeView,
        context: Context
    ) -> CGSize? {
        // Return an explicit size based on the proposed width and CodeView's capped height.
        // Returning nil forces SwiftUI to call intrinsicContentSize on every proposed-size
        // pass, which recomputes fullCodeContentHeight() redundantly during streaming.
        let width = proposal.width ?? UIScreen.main.bounds.width
        let height = min(uiView.intrinsicContentSize.height, CodeViewConfiguration.maxCodeViewHeight)
        return CGSize(width: width, height: height)
    }
}
#endif
