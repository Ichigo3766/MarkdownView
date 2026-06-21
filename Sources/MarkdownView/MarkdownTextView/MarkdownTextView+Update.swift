//
//  MarkdownTextView+Update.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import CoreText
import Litext
import UIKit

extension MarkdownTextView {
    func updateTextExecute() {
        assert(Thread.isMainThread)

        let newBlocks = document.blocks

        // ── Fast path: empty document ──────────────────────────────────────
        if newBlocks.isEmpty {
            cachedBlockSegments.removeAll()
            cachedAttributedString = .init()
            let oldViews = contextViews
            contextViews.removeAll()
            for view in oldViews { view.removeFromSuperview() }
            textView.attributedText = NSAttributedString()
            textView.setNeedsLayout()
            setNeedsLayout()
            textView.setNeedsDisplay()
            setNeedsDisplay()
            return
        }

        // ── Find the first block that has changed ─────────────────────────
        // Compare incoming blocks against cache using Equatable.
        // Blocks before `firstDirtyIndex` are identical and can be reused.
        let cachedBlocks = cachedBlockSegments
        var firstDirtyIndex = min(newBlocks.count, cachedBlocks.count)
        for i in 0 ..< firstDirtyIndex {
            if newBlocks[i] != cachedBlocks[i].node {
                firstDirtyIndex = i
                break
            }
        }

        // All blocks matched — nothing to do (theme hasn't changed either
        // since that clears the cache via reset()).
        if firstDirtyIndex == newBlocks.count, newBlocks.count == cachedBlocks.count {
            // Still wire up code delegates in case view was reused
            for view in contextViews {
                if let cv = view as? CodeView { cv.textView.delegate = self }
            }
            return
        }

        // ── Manage the view pool ──────────────────────────────────────────
        // Only stash views that belong to DIRTY (changed/removed) blocks.
        // The clean prefix's views never change, so they're never removed —
        // we only need to track the dirty-old views for cleanup, not the whole
        // contextViews set (avoids two O(n_views) Set allocations per frame).
        viewProvider.lockPool()
        defer { viewProvider.unlockPool() }

        // Stash only the views from segments that are being replaced
        let dirtyOldSegments = cachedBlocks.dropFirst(firstDirtyIndex)
        var dirtyOldViews: [UIView] = []
        for seg in dirtyOldSegments {
            for view in seg.subviews {
                dirtyOldViews.append(view)
                if let cv = view as? CodeView { viewProvider.stashCodeView(cv); continue }
                if let tv = view as? TableView { viewProvider.stashTableView(tv); continue }
            }
        }

        // Reorder pool to follow the dirty-old-views sequence for best reuse
        viewProvider.reorderViews(matching: dirtyOldViews)

        // ── Build new segments for dirty blocks only ───────────────────────
        var newSegments: [CachedBlockSegment] = []
        newSegments.reserveCapacity(newBlocks.count - firstDirtyIndex)

        for i in firstDirtyIndex ..< newBlocks.count {
            let node = newBlocks[i]
            let result = TextBuilder.buildSingleBlock(node: node, view: self, viewProvider: viewProvider)
            newSegments.append(.init(node: node, attributedString: result.document, subviews: result.subviews))
        }

        // ── Assemble the final cache ──────────────────────────────────────
        let cleanSegments = cachedBlocks.prefix(firstDirtyIndex)
        let allSegments = Array(cleanSegments) + newSegments
        cachedBlockSegments = allSegments

        // ── Mutate the persistent attributed string in-place ──────────────
        let cleanLength = cleanSegments.reduce(0) { $0 + $1.attributedString.length }
        let totalOldLength = cachedAttributedString.length

        cachedAttributedString.beginEditing()
        if totalOldLength > cleanLength {
            cachedAttributedString.deleteCharacters(in: NSRange(location: cleanLength, length: totalOldLength - cleanLength))
        }
        for seg in newSegments {
            cachedAttributedString.append(seg.attributedString)
        }
        cachedAttributedString.endEditing()

        textView.attributedText = cachedAttributedString

        // ── Update contextViews ───────────────────────────────────────────
        contextViews = allSegments.flatMap(\.subviews)

        // Wire code view delegates for new segments
        for seg in newSegments {
            for view in seg.subviews {
                if let cv = view as? CodeView { cv.textView.delegate = self }
            }
        }

        // ── Remove views that are no longer in use ────────────────────────
        // Only the dirty-old views could have been removed (clean-prefix views
        // are always retained). A dirty-old view that isn't present in the new
        // segments' views is gone → remove from superview.
        if !dirtyOldViews.isEmpty {
            let newViewsSet = Set(newSegments.flatMap(\.subviews))
            for goneView in dirtyOldViews where !newViewsSet.contains(goneView) {
                goneView.removeFromSuperview()
            }
        }

        textView.setNeedsLayout()
        setNeedsLayout()

        textView.setNeedsDisplay()
        setNeedsDisplay()
    }
}
