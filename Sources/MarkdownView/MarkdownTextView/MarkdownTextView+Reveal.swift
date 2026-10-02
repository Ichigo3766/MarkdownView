//
//  MarkdownTextView+Reveal.swift
//  MarkdownView
//
//  Draw-time text reveal. The text is laid out once in full; characters past the
//  reveal position are simply not painted, and the few just before it fade in.
//

import Litext
import UIKit

public extension MarkdownTextView {
    /// Reveals the first `progress` (0...1) share of the visible characters and fades in the last
    /// `fadeCharacters` of them. `nil` shows everything.
    ///
    /// Visible characters exclude line feeds and list-marker placeholders. The
    /// position is fractional so the fade edge moves continuously.
    func setReveal(progress: Double?, fadeCharacters: CGFloat) {
        guard let progress else {
            revealProgress = nil
            textView.revealFade = 0
            textView.revealLimit = nil
            if textView.revealsHeight {
                textView.revealsHeight = false
                invalidateIntrinsicContentSize()
            }
            return
        }
        revealProgress = progress
        revealFadeCharacters = fadeCharacters
        textView.revealsHeight = true
        applyReveal()
    }

    /// Total visible characters in the laid-out text.
    var revealableCharacterCount: Int {
        revealableOffsets().count
    }
}

extension MarkdownTextView {
    func applyReveal() {
        guard let progress = revealProgress else { return }
        let offsets = revealableOffsets()
        let count = min(max(progress, 0), 1) * Double(offsets.count)
        let whole = Int(count.rounded(.down))
        let previousHeight = textView.lastRevealedHeight
        if whole < offsets.count {
            let fraction = CGFloat(count - Double(whole))
            textView.revealFade = revealFadeCharacters
            textView.revealLimit = CGFloat(offsets[whole]) + fraction
        } else {
            textView.revealFade = 0
            textView.revealLimit = nil
        }
        if textView.lastRevealedHeight != previousHeight {
            invalidateIntrinsicContentSize()
        }
    }

    /// UTF-16 offsets of every visible character, cached per attributed string.
    func revealableOffsets() -> [Int] {
        if let revealOffsets { return revealOffsets }
        let string = textView.attributedText
        let text = string.string as NSString
        var result: [Int] = []
        result.reserveCapacity(text.length)
        for index in 0 ..< text.length {
            let unit = text.character(at: index)
            if unit == 0x0A { continue }
            if unit == 0xFFFC,
               string.attribute(.ltxLineDrawingCallback, at: index, effectiveRange: nil) != nil {
                continue
            }
            // Skip the trailing half of a surrogate pair.
            if unit >= 0xDC00, unit <= 0xDFFF { continue }
            result.append(index)
        }
        revealOffsets = result
        return result
    }
}
