//
//  MarkdownTextView+Update.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import CoreText
import Litext
import UIKit

// MARK: - Scroll preservation helpers

private extension UIView {
    /// Walks up the view hierarchy to find the nearest ancestor UIScrollView.
    var nearestScrollView: UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let sv = view as? UIScrollView { return sv }
            candidate = view.superview
        }
        return nil
    }
}

private extension UIScrollView {
    /// Returns true when the scroll view is scrolled to (or very near) its bottom.
    var isNearBottom: Bool {
        let maxOffset = contentSize.height - bounds.height + contentInset.bottom
        guard maxOffset > 0 else { return true }
        return contentOffset.y >= maxOffset - 40  // 40pt slack
    }
}

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
        // Views belonging to the clean prefix are kept in contextViews and
        // must NOT be stashed — they're still referenced by cached attrstrings.
        viewProvider.lockPool()
        defer { viewProvider.unlockPool() }

        // Collect the full set of old views for cleanup tracking
        let oldContextViewsSet = Set(contextViews)

        // Stash only the views from segments that are being replaced
        let dirtyOldSegments = cachedBlocks.dropFirst(firstDirtyIndex)
        var dirtyOldViews: [UIView] = []
        for seg in dirtyOldSegments {
            for view in seg.subviews {
                dirtyOldViews.append(view)
                if let cv = view as? CodeView { viewProvider.stashCodeView(cv); continue }
                if let tv = view as? TableView { viewProvider.stashTableView(tv); continue }
                assertionFailure("Unknown subview type in cached segment")
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

        // ── Scroll-position preservation ──────────────────────────────────
        // When the user has manually scrolled up to read earlier content,
        // setting attributedText causes the parent scroll view to jump back
        // to the bottom (because the content height changes and SwiftUI
        // invalidates layout). We capture the scroll offset before the update
        // and restore it after layout if the user was NOT at the bottom.
        let scrollView = nearestScrollView
        let userScrolledUp = scrollView.map { !$0.isNearBottom } ?? false
        let savedOffset = scrollView?.contentOffset

        textView.attributedText = cachedAttributedString

        // Restore the saved scroll position after the layout pass so the view
        // stays put. We defer by one run-loop cycle so the layout has settled.
        if userScrolledUp, let sv = scrollView, let offset = savedOffset {
            DispatchQueue.main.async {
                // Only restore if the user is still scrolled up (they may have
                // scrolled to bottom again in the tiny gap).
                if !sv.isNearBottom || sv.contentOffset.y < offset.y {
                    sv.setContentOffset(offset, animated: false)
                }
            }
        }

        // ── Update contextViews ───────────────────────────────────────────
        contextViews = allSegments.flatMap(\.subviews)

        // Wire code view delegates for new segments
        for seg in newSegments {
            for view in seg.subviews {
                if let cv = view as? CodeView { cv.textView.delegate = self }
            }
        }

        // ── Remove views that are no longer in use ────────────────────────
        let currentViewsSet = Set(contextViews)
        for goneView in oldContextViewsSet where !currentViewsSet.contains(goneView) {
            goneView.removeFromSuperview()
        }

        textView.setNeedsLayout()
        setNeedsLayout()

        textView.setNeedsDisplay()
        setNeedsDisplay()
    }
}
