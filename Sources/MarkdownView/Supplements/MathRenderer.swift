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
        let cacheKey = renderCacheKey(for: latex, fontSize: fontSize, textColor: textColor)
        if let cachedImage = renderCache.value(forKey: cacheKey) {
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

        guard error == nil, let image else {
            #if DEBUG
            print("[!] MathRenderer failed to render: \(latex) \(error?.localizedDescription ?? "?")")
            #endif
            return nil
        }

        let result = image.withRenderingMode(.alwaysTemplate).withTintColor(.label)
        renderCache.setValue(result, forKey: cacheKey)
        return result
    }

    private static func renderCacheKey(for latex: String, fontSize: CGFloat, textColor: PlatformColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolvedColor = textColor.resolvedColor(with: UITraitCollection.current)
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
