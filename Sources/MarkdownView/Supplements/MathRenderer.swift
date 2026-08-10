//
//  MathRenderer.swift
//  MarkdownView
//
//  Created by 秋星桥 on 5/26/25.
//

import Foundation
import Litext
import LRUCache
import SwiftMath
import UIKit

public enum MathRenderer {
    static let renderCache = LRUCache<String, PlatformImage>(countLimit: 256)
    /// Protects renderCache from concurrent reads/writes on background threads.
    /// LRUCache is not thread-safe; multiple Task.detached math-render workers
    /// can race on the shared cache and corrupt its internal linked-list state,
    /// which causes the WTF::ParkingLot / MTMathListBuilder crashes seen in prod.
    private static let cacheLock = NSLock()

    private static func preprocessLatex(_ latex: String) -> String {
        latex
            // Ellipses & logic operators SwiftMath doesn't define.
            .replacingOccurrences(of: "\\dots", with: "\\ldots")
            .replacingOccurrences(of: "\\implies", with: "\\Rightarrow")
            .replacingOccurrences(of: "\\impliedby", with: "\\Leftarrow")
            .replacingOccurrences(of: "\\iff", with: "\\Leftrightarrow")
            .replacingOccurrences(of: "\\to", with: "\\rightarrow")
            .replacingOccurrences(of: "\\gets", with: "\\leftarrow")
            // Environments SwiftMath maps to its supported equivalents.
            .replacingOccurrences(of: "\\begin{align}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align}", with: "\\end{aligned}")
            .replacingOccurrences(of: "\\begin{align*}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align*}", with: "\\end{aligned}")
            .replacingOccurrences(of: "\\begin{equation}", with: "")
            .replacingOccurrences(of: "\\end{equation}", with: "")
            .replacingOccurrences(of: "\\begin{equation*}", with: "")
            .replacingOccurrences(of: "\\end{equation*}", with: "")
            .replacingOccurrences(of: "\\begin{gather}", with: "\\begin{gathered}")
            .replacingOccurrences(of: "\\end{gather}", with: "\\end{gathered}")
            .replacingOccurrences(of: "\\begin{gather*}", with: "\\begin{gathered}")
            .replacingOccurrences(of: "\\end{gather*}", with: "\\end{gathered}")
            .replacingOccurrences(of: "\\begin{cases}", with: "\\left\\{\\begin{matrix}")
            .replacingOccurrences(of: "\\end{cases}", with: "\\end{matrix}\\right.")
            // Fraction variants → plain \frac.
            .replacingOccurrences(of: "\\dfrac", with: "\\frac")
            .replacingOccurrences(of: "\\tfrac", with: "\\frac")
            // Spacing macros SwiftMath ignores/doesn't support.
            .replacingOccurrences(of: "\\!", with: "")
            .replacingOccurrences(of: "\\;", with: "\\ ")
            .replacingOccurrences(of: "\\:", with: "\\ ")
            .replacingOccurrences(of: "\\,", with: "\\ ")
            // \tag{...} is meaningless for inline rendering — strip it.
            .replacingTagCommand()
            .replacingOperatornameCommand()
            .replacingBoxedCommand()
    }

    public static func renderToImage(
        latex: String,
        fontSize: CGFloat = 16,
        textColor: PlatformColor = .black
    ) -> PlatformImage? {
        // Build the cache key using a background-thread-safe color resolution.
        // UITraitCollection.current must NOT be accessed on a background thread
        // (it triggers a main-thread-only UIKit traversal which races with the
        // JS engine's GC and causes the WTF::ParkingLot crash seen in production).
        // We resolve the color using a neutral UITraitCollection() so the key
        // is deterministic and fully safe to compute on any thread.
        let cacheKey = renderCacheKeyThreadSafe(for: latex, fontSize: fontSize, textColor: textColor)

        // Thread-safe cache read.
        if let cachedImage = cacheLock.withLock({ renderCache.value(forKey: cacheKey) }) {
            return cachedImage
        }

        let processedLatex = preprocessLatex(latex)
        let resolvedTextColor = textColor

        let mathImage = MTMathImage(
            latex: processedLatex,
            fontSize: fontSize,
            textColor: resolvedTextColor,
            labelMode: .text
        )
        let (error, image) = mathImage.asImage()

        if let error = error {
            #if DEBUG
            print("[MathRenderer] ❌ FAILED for latex='\(latex.prefix(80))' error=\(error.localizedDescription)")
            #endif
            return nil
        }
        guard let image else { return nil }

        let result = image.withRenderingMode(.alwaysTemplate).withTintColor(.label)
        // Thread-safe cache write.
        cacheLock.withLock { renderCache.setValue(result, forKey: cacheKey) }
        return result
    }

    /// Builds a stable cache key without touching UITraitCollection.current.
    ///
    /// The old `renderCacheKey` called `textColor.resolvedColor(with: UITraitCollection.current)`
    /// on a background thread, which is undefined behaviour (UITraitCollection.current walks
    /// the UIView hierarchy on the main thread). We now use a fixed UITraitCollection() for
    /// RGBA resolution — the colour used for *rendering* is still the exact `textColor` passed
    /// in; this fixed resolution only affects the cache-key string, and using a neutral
    /// trait collection is perfectly stable and deterministic across calls.
    private static func renderCacheKeyThreadSafe(
        for latex: String,
        fontSize: CGFloat,
        textColor: PlatformColor
    ) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // Use a fixed (neutral) trait collection instead of UITraitCollection.current
        // so this is safe to call from any thread.
        let resolvedColor = textColor.resolvedColor(with: UITraitCollection())
        resolvedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(latex)#\(fontSize)#\(r),\(g),\(b),\(a)"
    }
}

// MARK: - String Extension

private extension String {
    func substring(with range: NSRange) -> String? {
        guard let swiftRange = Range(range, in: self) else { return nil }
        return String(self[swiftRange])
    }

    /// Strips `\tag{...}` (equation numbering) — meaningless for inline rendering.
    func replacingTagCommand() -> String {
        var result = self
        while let range = result.range(of: "\\tag{") {
            let startIndex = range.upperBound
            var braceCount = 1
            var endIndex = startIndex

            while endIndex < result.endIndex, braceCount > 0 {
                let char = result[endIndex]
                if char == "{" { braceCount += 1 }
                else if char == "}" { braceCount -= 1 }
                if braceCount > 0 { endIndex = result.index(after: endIndex) }
            }

            if braceCount == 0 {
                let fullRange = range.lowerBound ... endIndex
                result.replaceSubrange(fullRange, with: "")
            } else {
                result.replaceSubrange(range, with: "")
                break
            }
        }
        return result
    }

    /// Converts \operatorname{foo} → \mathrm{foo} so SwiftMath can render it.
    func replacingOperatornameCommand() -> String {
        var result = self
        while let range = result.range(of: "\\operatorname{") {
            let startIndex = range.upperBound
            var braceCount = 1
            var endIndex = startIndex

            while endIndex < result.endIndex, braceCount > 0 {
                let char = result[endIndex]
                if char == "{" { braceCount += 1 }
                else if char == "}" { braceCount -= 1 }
                if braceCount > 0 { endIndex = result.index(after: endIndex) }
            }

            if braceCount == 0 {
                let content = String(result[startIndex ..< endIndex])
                let fullRange = range.lowerBound ... endIndex
                result.replaceSubrange(fullRange, with: "\\mathrm{\(content)}")
            } else {
                result.replaceSubrange(range, with: "\\mathrm{")
                break
            }
        }
        return result
    }

    func replacingBoxedCommand() -> String {
        var result = self
        while let range = result.range(of: "\\boxed{") {
            let startIndex = range.upperBound
            var braceCount = 1
            var endIndex = startIndex

            while endIndex < result.endIndex, braceCount > 0 {
                let char = result[endIndex]
                if char == "{" { braceCount += 1 }
                else if char == "}" { braceCount -= 1 }
                if braceCount > 0 { endIndex = result.index(after: endIndex) }
            }

            if braceCount == 0 {
                let content = String(result[startIndex ..< endIndex])
                let fullRange = result.index(range.lowerBound, offsetBy: 0) ... endIndex
                result.replaceSubrange(fullRange, with: content)
            } else {
                result.replaceSubrange(range, with: "")
                break
            }
        }
        return result
    }
}
