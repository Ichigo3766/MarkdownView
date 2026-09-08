//
//  PreprocessedContent+Split.swift
//  MarkdownView
//
//  Splits a fully-parsed PreprocessedContent into a series of smaller
//  PreprocessedContent "chunks" so that a giant message can be rendered as a
//  plain VStack of small MarkdownTextViews instead of a single enormous one.
//
//  ## Why
//  Litext's LTXLabel is O(document) for measure (CTFramesetterSuggestFrameSize),
//  layout (CTFramesetterCreateFrame), highlight-region extraction, AND draw
//  (CTFrameDraw) — all synchronous, on the main thread, with no viewport
//  virtualization. A single 70k-word message therefore blocks the main thread
//  hard on first layout. Splitting the message into many small labels bounds
//  every individual CoreText pass to one chunk, so no single pass is ever large.
//
//  ## Why sharing the maps is safe
//  - `highlightMaps` are keyed by a CONTENT hash (CodeHighlighter.key(for:language:))
//    — never by block index. A chunk that contains a code block finds its map by
//    hashing its own content, so handing every chunk the full map is correct.
//  - `rendered` (math images) is keyed by the placeholder replacement strings that
//    are embedded directly in the inline text. A chunk only ever looks up the
//    placeholders that appear in its own text.
//  So we can share the SAME `rendered` / `highlightMaps` references across every
//  chunk with zero key remapping and zero risk of a chunk missing its math image
//  or syntax colors.
//

import Foundation
import MarkdownParser

public extension MarkdownTextView.PreprocessedContent {
    /// Approximate target size (in characters) for a coalesced text chunk.
    /// Adjacent "light" blocks (paragraphs, headings, thematic breaks, lists,
    /// quotes) are grouped up to roughly this size so we don't spawn one tiny
    /// LTXLabel per paragraph. "Heavy" blocks (code, tables) always stand alone
    /// so their dedicated subviews are never grouped with unrelated text.
    static let defaultChunkCharBudget = 1800

    /// Splits this content into an ordered array of smaller PreprocessedContent
    /// chunks. Each chunk shares this instance's `rendered` / `highlightMaps`
    /// (safe — see file header).
    ///
    /// - Parameter chunkCharBudget: soft target for coalesced light-block chunks.
    /// - Returns: chunks in document order. Returns `[self]` when there is 0 or 1
    ///   block (nothing to gain from splitting).
    func split(chunkCharBudget: Int = MarkdownTextView.PreprocessedContent.defaultChunkCharBudget) -> [MarkdownTextView.PreprocessedContent] {
        guard blocks.count > 1 else { return [self] }

        var chunks: [MarkdownTextView.PreprocessedContent] = []
        var pending: [MarkdownBlockNode] = []
        var pendingWeight = 0

        func flushPending() {
            guard !pending.isEmpty else { return }
            chunks.append(makeChunk(blocks: pending))
            pending.removeAll(keepingCapacity: true)
            pendingWeight = 0
        }

        for node in blocks {
            if node.isHeavyForSplitting {
                // Heavy blocks stand alone.
                flushPending()
                chunks.append(makeChunk(blocks: [node]))
                continue
            }

            pending.append(node)
            pendingWeight += node.approxWeightForSplitting
            if pendingWeight >= chunkCharBudget {
                flushPending()
            }
        }
        flushPending()

        // Defensive: never return empty.
        return chunks.isEmpty ? [self] : chunks
    }

    /// Builds a chunk that reuses the shared rendered/highlight maps.
    private func makeChunk(blocks: [MarkdownBlockNode]) -> MarkdownTextView.PreprocessedContent {
        MarkdownTextView.PreprocessedContent(
            blocks: blocks,
            rendered: rendered,
            highlightMaps: highlightMaps
        )
    }
}

// MARK: - Block weighting for chunk boundaries

private extension MarkdownBlockNode {
    /// Blocks that host their own dedicated UIView subview (CodeView/TableView)
    /// and can be individually expensive — always isolated into their own chunk.
    var isHeavyForSplitting: Bool {
        switch self {
        case .codeBlock, .table:
            return true
        default:
            return false
        }
    }

    /// A rough character weight used only to decide chunk boundaries.
    var approxWeightForSplitting: Int {
        switch self {
        case let .codeBlock(_, content):
            return content.count
        case let .paragraph(content):
            return content.plainTextApproxCount
        case let .heading(_, content):
            return content.plainTextApproxCount
        case let .blockquote(children):
            return children.reduce(0) { $0 + $1.approxWeightForSplitting }
        case let .callout(_, children):
            return children.reduce(0) { $0 + $1.approxWeightForSplitting }
        case let .bulletedList(_, items):
            return items.reduce(0) { $0 + $1.children.reduce(0) { $0 + $1.approxWeightForSplitting } }
        case let .numberedList(_, _, items):
            return items.reduce(0) { $0 + $1.children.reduce(0) { $0 + $1.approxWeightForSplitting } }
        case let .taskList(_, items):
            return items.reduce(0) { $0 + $1.children.reduce(0) { $0 + $1.approxWeightForSplitting } }
        case let .table(_, rows):
            return rows.reduce(0) { $0 + $1.cells.count } * 8
        case .thematicBreak:
            return 1
        }
    }
}

private extension Array where Element == MarkdownInlineNode {
    /// Cheap approximate plain-text length of an inline run for chunk sizing.
    var plainTextApproxCount: Int {
        reduce(0) { $0 + $1.plainTextApproxCount }
    }
}

private extension MarkdownInlineNode {
    var plainTextApproxCount: Int {
        switch self {
        case let .text(s):
            return s.count
        case let .code(s):
            return s.count
        case let .html(s):
            return s.count
        case let .math(content, _):
            return content.count
        case .softBreak, .lineBreak:
            return 1
        case let .emphasis(children):
            return children.plainTextApproxCount
        case let .strong(children):
            return children.plainTextApproxCount
        case let .strikethrough(children):
            return children.plainTextApproxCount
        case let .link(_, children):
            return children.plainTextApproxCount
        case let .image(_, children):
            return children.plainTextApproxCount
        }
    }
}
