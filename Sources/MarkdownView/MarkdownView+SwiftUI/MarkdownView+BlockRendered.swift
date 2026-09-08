//
//  MarkdownView+BlockRendered.swift
//  MarkdownView
//
//  Renders a large, finished (non-streaming) message as a plain VStack of small
//  per-chunk MarkdownViews instead of one giant LTXLabel.
//
//  Each chunk is a small PreprocessedContent produced by `split()`, so every
//  individual CoreText typeset / layout / draw pass is bounded to one chunk —
//  the main thread is never blocked by a single enormous string. Parsing + math
//  rendering + splitting happen once, off-main, via MarkdownBlockRenderCache and
//  are reused on every subsequent appearance (instant re-scroll).
//
//  This deliberately uses a plain `VStack` (NOT LazyVStack) to satisfy the host
//  app's requirement. The performance win comes from bounding per-chunk work and
//  caching — not from row virtualization.
//

import SwiftUI

/// Internal SwiftUI view that renders finished markdown as chunked small views.
struct BlockRenderedMarkdownView: View {
    let text: String
    let theme: MarkdownTheme
    let codeBlockBarHidden: Bool
    let citationSources: [Int: URL]
    /// Soft target chunk size passed through to `split()`.
    let chunkCharBudget: Int

    /// Resolved chunks. `nil` until the async build completes (or a synchronous
    /// cache hit populates it immediately in `resolvedChunks`).
    @State private var chunks: [MarkdownTextView.PreprocessedContent]? = nil
    /// The (content, themeSignature) the current `chunks` were built for, so we
    /// rebuild when either changes.
    @State private var builtKey: Int = 0
    @State private var buildInFlight: Bool = false

    var body: some View {
        let key = MarkdownBlockRenderCache.key(content: text, theme: theme)

        // Synchronous cache hit: render immediately with no async round-trip.
        let resolved: [MarkdownTextView.PreprocessedContent]? = {
            if builtKey == key, let chunks { return chunks }
            if let hit = MarkdownBlockRenderCache.shared.lookup(content: text, theme: theme) {
                return hit
            }
            return nil
        }()

        Group {
            if let resolved {
                chunkedStack(resolved)
            } else {
                // Cache miss: the off-main split is running. We deliberately do NOT
                // render the full single MarkdownView here — laying out a 70k-word
                // string even for one frame is the exact main-thread stall we are
                // eliminating (and it would happen behind the app's loading curtain,
                // so the user would still feel the freeze on open).
                //
                // Instead reserve an estimated height so there is no hard scroll jump
                // when the real chunks land a moment later. The estimate is a rough
                // chars-per-line heuristic; a small correction on settle is fine and
                // is invisible under the app's load curtain on first open.
                Color.clear
                    .frame(height: estimatedHeight)
                    .accessibilityHidden(true)
            }
        }

        .onAppear { ensureBuild(key: key) }
        .onChange(of: key) { _ in
            // Content or theme changed — resolve for the new key.
            chunks = nil
            ensureBuild(key: key)
        }
    }

    /// Rough placeholder height so a cache-miss doesn't collapse the row before
    /// the real chunks arrive. Assumes ~55 characters per line at the current
    /// body font. This only needs to be in the right ballpark — a small height
    /// correction on settle is acceptable (and hidden by the app's load curtain
    /// on first open).
    private var estimatedHeight: CGFloat {
        let lineHeight = theme.fonts.body.lineHeight + theme.spacings.lineSpacing
        let approxCharsPerLine = 55.0
        let approxLines = max(1.0, Double(text.count) / approxCharsPerLine)
        return CGFloat(approxLines) * lineHeight
    }

    @ViewBuilder
    private func chunkedStack(_ chunks: [MarkdownTextView.PreprocessedContent]) -> some View {

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                MarkdownView(chunk, theme: theme)
                    .codeBarHidden(codeBlockBarHidden)
            }
        }
    }

    private func ensureBuild(key: Int) {
        // Already resolved for this key, or a cache hit exists — sync state.
        if builtKey == key, chunks != nil { return }
        if let hit = MarkdownBlockRenderCache.shared.lookup(content: text, theme: theme) {
            chunks = hit
            builtKey = key
            return
        }
        guard !buildInFlight else { return }
        buildInFlight = true

        MarkdownBlockRenderCache.shared.build(
            content: text,
            theme: theme,
            chunkCharBudget: chunkCharBudget
        ) { built in
            // Only apply if the key still matches the current content/theme.
            let currentKey = MarkdownBlockRenderCache.key(content: text, theme: theme)
            buildInFlight = false
            guard currentKey == key else { return }
            chunks = built
            builtKey = key
        }
    }
}
