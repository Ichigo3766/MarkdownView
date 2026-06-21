//
//  IncrementalStreamingParser.swift
//  MarkdownView
//

import Foundation
import MarkdownParser

/// Incremental markdown parser for streaming content.
///
/// ## Problem
/// During streaming, `displayContent` grows by 1–4 characters per drain tick
/// (up to 60 times/sec). Without caching, this triggers a full
/// `MarkdownParser().parse(fullText)` call on every tick — O(n) work each
/// frame, O(n²) total. For a 3,000-word response that means tens of millions
/// of parse operations.
///
/// ## Solution
/// Maintain a "stable prefix" — everything before the last completed block
/// boundary (double-newline). The stable prefix is parsed once and cached.
/// On each subsequent tick, only the short "live tail" (from the last block
/// boundary onward) needs to be re-parsed and merged with the cached result.
///
/// ## Incremental fence scanning
/// Because the model output is **append-only** during a stream (verified each
/// tick by `newText.hasPrefix(cachedText)`), the fence/boundary scan does NOT
/// need to re-read the whole document every tick. We cache:
///   - the line-by-line scan cursor (offset + `String.Index`) up to the last
///     processed line boundary,
///   - the running "inside fence" state and fence-start offset,
///   - all fenced ranges discovered so far,
///   - all `\n\n` boundary offsets discovered so far.
/// Each tick we only scan the freshly-appended suffix → O(delta), not O(n).
///
/// ## Safety
/// When text is reset (regeneration, new message) — detected by
/// `!newText.hasPrefix(cachedText)` — all incremental scan state is cleared and
/// a fresh scan runs for that tick.
final class IncrementalStreamingParser {

    // MARK: - Cached Stable Prefix

    /// The stable prefix text that has been cached (everything before the last
    /// completed block boundary). Plain `String` — no stored indices.
    private var cachedText: String = ""

    /// Cached character count of `cachedText` to avoid O(n) `.count` each tick.
    private var cachedTextCount: Int = 0

    /// Pre-parsed blocks for `cachedText`.
    private var cachedBlocks: [MarkdownBlockNode] = []

    /// Rendered math images for the stable cached portion. Rendered once (off
    /// the drain thread) when the stable boundary advances, then reused every
    /// tick so settled equations appear live during streaming rather than
    /// snapping in at stream end. The live tail still shows raw LaTeX until it
    /// settles into the stable prefix.
    private var cachedRendered: RenderedTextContent.Map = [:]

    /// The theme used when building `cachedBlocks`.
    private var cachedTheme: MarkdownTheme = .default

    // MARK: - Incremental Scan State

    /// All text that has been line-scanned so far is `scannedText`. On the next
    /// tick (append-only), only the suffix after `scannedText` needs scanning.
    private var scannedText: String = ""
    /// Character offset where the next unscanned line begins.
    private var scanCharOffset: Int = 0
    /// Whether the scan is currently inside an unclosed code fence.
    private var scanInsideFence: Bool = false
    /// Character offset of the opening ``` line when `scanInsideFence` is true.
    private var scanFenceStart: Int = 0
    /// Fenced (start, end) character ranges discovered so far (closed fences).
    private var scanFencedRanges: [(Int, Int)] = []
    /// Character offsets (upper-bound of each "\n\n") discovered so far.
    private var scanBoundaryOffsets: [Int] = []

    // MARK: - Tuning

    /// Minimum number of characters that must remain in the "live tail" after
    /// the stable boundary. 30 chars is roughly 1–2 sentences.
    private static let minTailLength: Int = 30

    // MARK: - Public API

    /// Clears all cached state. Call this when starting a new streaming session
    /// so stale stable-prefix data from the previous message doesn't leak.
    func reset() {
        cachedText = ""
        cachedTextCount = 0
        cachedBlocks = []
        cachedRendered = [:]
        resetScanState()
    }

    private func resetScanState() {
        scannedText = ""
        scanCharOffset = 0
        scanInsideFence = false
        scanFenceStart = 0
        scanFencedRanges.removeAll(keepingCapacity: true)
        scanBoundaryOffsets.removeAll(keepingCapacity: true)
    }

    /// Returns a `PreprocessedContent` for `newText`, reusing as much cached
    /// state as possible.
    func parse(
        _ newText: String,
        theme: MarkdownTheme
    ) -> MarkdownTextView.PreprocessedContent {

        // ── 1. Theme change → full reset ──────────────────────────────────
        if theme != cachedTheme {
            reset()
            cachedTheme = theme
        }

        // ── 2. Text reset / shrinkage → cache is invalid ──────────────────
        // `hasPrefix` is safe: returns false (never crashes) when lengths differ
        // or content changed. This covers regeneration, stop-and-restart, etc.
        if !newText.hasPrefix(scannedText) {
            reset()
            cachedTheme = theme
        }

        // ── 3. Find stable boundary in newText (incremental) ──────────────
        let stableBoundaryOffset = findStableBoundaryOffset(in: newText)

        // ── 4. Build tail text ────────────────────────────────────────────
        let tailText: String
        if stableBoundaryOffset == 0 {
            tailText = newText
        } else {
            let boundaryIdx = newText.index(newText.startIndex, offsetBy: stableBoundaryOffset)
            tailText = String(newText[boundaryIdx...])
        }

        // ── 5. Parse the live tail (always small) ─────────────────────────
        let parser = MarkdownParser()
        let tailResult = parser.parse(tailText)

        // ── 6. Update stable cache if the boundary advanced ───────────────
        if stableBoundaryOffset > cachedTextCount {
            let newStableEndIdx = newText.index(newText.startIndex, offsetBy: stableBoundaryOffset)
            let newStableText = String(newText[..<newStableEndIdx])
            let stableResult = parser.parse(newStableText)
            cachedBlocks = stableResult.document
            cachedText = newStableText
            cachedTextCount = stableBoundaryOffset

            // Render the stable portion's math ONCE here (we're already off the
            // main thread). Reused every subsequent tick → equations in settled
            // text appear live during streaming instead of snapping in at the end.
            cachedRendered = Self.renderMath(stableResult.mathContext, theme: theme)
        }

        // ── 7. Merge stable + tail ────────────────────────────────────────
        let allBlocks = cachedBlocks + tailResult.document

        // The live tail is re-parsed independently each tick, so its math
        // replacement identifiers restart at 0 and would COLLIDE with the
        // stable portion's identifiers in the shared `rendered` map. To stay
        // correct we only expose the pre-rendered stable math when the tail
        // contains no equations of its own; otherwise we fall back to raw
        // LaTeX for this tick (it resolves once the stream settles / finishes).
        let rendered: RenderedTextContent.Map = tailResult.mathContext.isEmpty ? cachedRendered : [:]

        return MarkdownTextView.PreprocessedContent(
            blocks: allBlocks,
            rendered: rendered,
            highlightMaps: [:],
            mathContext: [:]
        )
    }

    /// Synchronously renders a math context to images. Called on the parser's
    /// background thread (never the main/drain thread).
    private static func renderMath(
        _ mathContext: [Int: String],
        theme: MarkdownTheme
    ) -> RenderedTextContent.Map {
        guard !mathContext.isEmpty else { return [:] }
        var map: RenderedTextContent.Map = [:]
        for (key, value) in mathContext {
            let image = MathRenderer.renderToImage(
                latex: value,
                fontSize: theme.fonts.body.pointSize,
                textColor: theme.colors.body
            )?.withRenderingMode(.alwaysTemplate)
            let replacementText = MarkdownParser.replacementText(for: .math, identifier: .init(key))
            map[replacementText] = RenderedTextContent(image: image, text: value)
        }
        return map
    }

    // MARK: - Private: Incremental Boundary Detection

    /// Returns the character offset of the start of the live tail — i.e., the
    /// position right after the last `\n\n` outside a code fence that leaves at
    /// least `minTailLength` characters remaining.
    ///
    /// Incrementally scans only the suffix appended since the previous call.
    private func findStableBoundaryOffset(in text: String) -> Int {
        // ── Scan only the freshly-appended suffix ────────────────────────
        // `scannedText` is always a prefix of `text` (guaranteed by the
        // hasPrefix reset in parse()). We continue line scanning from
        // `scanCharOffset`.
        scanNewSuffix(in: text)

        let totalCount = scanCharOffset  // characters scanned so far == text.count
        let minTail = Self.minTailLength
        guard totalCount > minTail + 2 else { return 0 }

        // When the text ends inside an unclosed fence, constrain candidate
        // boundaries to positions before that open fence's start.
        let openFenceSearchCap = scanInsideFence ? scanFenceStart : totalCount
        let searchEndOffset = min(totalCount - minTail, openFenceSearchCap)
        guard searchEndOffset > 0 else { return 0 }

        // Walk cached \n\n boundary offsets backwards, returning the last one
        // that qualifies (before searchEndOffset and outside any fence).
        for offset in scanBoundaryOffsets.reversed() {
            guard offset <= searchEndOffset else { continue }
            if !isInsideFence(offset) {
                return offset
            }
        }
        return 0
    }

    /// Continues the line-by-line scan from `scanCharOffset` over the newly
    /// appended suffix of `text`, updating fence state + boundary offsets.
    private func scanNewSuffix(in text: String) {
        // Resume at the stored char offset. We re-derive the String.Index from
        // the offset once (O(scanCharOffset)) only when the scan first resumes;
        // subsequent line walks advance the index directly.
        guard scanCharOffset <= text.count else {
            // Defensive: shouldn't happen given the hasPrefix guard.
            resetScanState()
            return
        }

        var lineStart = text.index(text.startIndex, offsetBy: scanCharOffset)
        var charOffset = scanCharOffset

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex

            // Only process a line once it is complete (terminated by \n) OR we
            // are at end-of-text. A line still mid-arrival (no \n yet and at
            // endIndex) is the live tail — we still account for fence toggling
            // but do not advance the persisted cursor past it so the next tick
            // re-reads it cleanly.
            let lineComplete = (lineEnd != text.endIndex)

            // Stop at the incomplete trailing line WITHOUT mutating any
            // persisted fence/boundary state. That partial line is the live
            // tail and will be re-scanned (complete) on a future tick. This
            // keeps the cached scan state derived only from complete lines.
            if !lineComplete {
                break
            }

            let lineLen = text.distance(from: lineStart, to: lineEnd)
            let lineOffsetStart = charOffset

            let linePrefix = text[lineStart..<lineEnd]
            if linePrefix.hasPrefix("```") {
                if scanInsideFence {
                    let fenceEnd = lineOffsetStart + lineLen
                    scanFencedRanges.append((scanFenceStart, fenceEnd))
                    scanInsideFence = false
                } else {
                    scanFenceStart = lineOffsetStart
                    scanInsideFence = true
                }
            }

            // Empty complete line → "\n\n" boundary. Upper bound = offset just
            // after this line's \n.
            if lineLen == 0 {
                scanBoundaryOffsets.append(lineOffsetStart + 1)
            }

            charOffset += lineLen + 1
            lineStart = text.index(after: lineEnd)
        }

        // Persist the cursor up to the last COMPLETE line boundary only.
        // The incomplete trailing line (if any) is re-scanned next tick.
        scanCharOffset = charOffset
        // scannedText tracks the prefix we've consumed for hasPrefix checks.
        if charOffset >= text.count {
            scannedText = text
        } else {
            scannedText = String(text[..<text.index(text.startIndex, offsetBy: charOffset)])
        }
    }

    /// Returns true if `offset` falls inside any closed fenced region, or after
    /// the start of an open (unclosed) fence.
    private func isInsideFence(_ offset: Int) -> Bool {
        if scanInsideFence, offset >= scanFenceStart { return true }
        for range in scanFencedRanges where offset >= range.0 && offset <= range.1 {
            return true
        }
        return false
    }
}
