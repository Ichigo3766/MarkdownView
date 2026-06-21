//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import Highlighter
import LRUCache
import UIKit

public typealias PlatformColor = UIColor

public final class CodeHighlighter: @unchecked Sendable {
    public typealias HighlightMap = [NSRange: PlatformColor]

    // LRU cache: 512 entries.
    public private(set) var renderCache = LRUCache<Int, HighlightMap>(countLimit: 512)

    // HighlighterSwift wraps a JSContext internally. JSContext is NOT thread-safe,
    // so all highlight() calls must be serialised onto this dedicated queue.
    private let highlightQueue = DispatchQueue(
        label: "com.markdownview.codehighlighter",
        qos: .userInitiated
    )

    // Two Highlighter instances — one per appearance.
    private let lightHighlighter: Highlighter?
    private let darkHighlighter: Highlighter?

    private init() {
        let light = Highlighter()
        light?.ignoreIllegals = true
        light?.setTheme("atom-one-light")
        self.lightHighlighter = light

        let dark = Highlighter()
        dark?.ignoreIllegals = true
        dark?.setTheme("atom-one-dark")
        self.darkHighlighter = dark
    }

    public static let current = CodeHighlighter()

    /// Call once from app launch to eagerly front-load the ~50-100 ms JSContext
    /// initialisation cost so the first code block doesn't pay it.
    public static func warmUp() {
        _ = CodeHighlighter.current
    }

    // MARK: - Key Generation

    /// Generates a stable cache key incorporating content, language, and appearance.
    public func key(for content: String, language: String?, isDark: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(language?.lowercased() ?? "")
        hasher.combine(isDark)
        return hasher.finalize()
    }

    /// Convenience overload — reads current appearance automatically.
    /// MUST be called on main thread (reads UITraitCollection.current).
    @MainActor
    public func key(for content: String, language: String?) -> Int {
        key(for: content, language: language, isDark: currentAppearanceIsDark())
    }

    // MARK: - Synchronous (cache-only, used during rendering)

    /// Returns cached highlight map if available, empty map otherwise.
    /// Does NOT trigger highlighting — CodeView triggers async highlighting.
    public func highlight(
        key: Int?,
        content: String,
        language: String?,
        theme: MarkdownTheme = .default
    ) -> HighlightMap {
        let isDark = currentAppearanceIsDark()
        let k = key ?? self.key(for: content, language: language, isDark: isDark)
        if let cached = renderCache.value(forKey: k) {
            return cached
        }
        return [:]
    }

    // MARK: - Async Lazy Highlighting (called by CodeView on appear)

    /// Asynchronously highlights code and returns a HighlightMap.
    /// Called by CodeView when content is set — lazy per-block.
    public func highlightAsync(
        content: String,
        language: String?,
        theme: MarkdownTheme = .default
    ) async -> HighlightMap {
        // Capture appearance on the calling (main) thread before hopping queues.
        let isDark = currentAppearanceIsDark()
        let cacheKey = key(for: content, language: language, isDark: isDark)

        // Check cache first — fast path, no JSContext overhead.
        if let cached = renderCache.value(forKey: cacheKey) {
            return cached
        }

        // Performance gate: don't waste JSContext overhead on trivially short snippets.
        guard content.count > 20 else { return [:] }

        // Performance cap: clamp very large blocks to avoid JSContext hangs.
        let maxHighlightLength = 50_000
        let highlightContent = content.count > maxHighlightLength
            ? String(content.prefix(maxHighlightLength))
            : content

        let lang = language?.lowercased() ?? ""

        // All JSContext calls must be serialised onto highlightQueue.
        let map: HighlightMap = await withCheckedContinuation { continuation in
            highlightQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }

                let highlighter = isDark ? self.darkHighlighter : self.lightHighlighter
                guard let highlighter else {
                    continuation.resume(returning: [:])
                    return
                }

                let nsAttrStr: NSAttributedString?

                if lang.isEmpty || lang == "plaintext" {
                    if highlightContent.count > 5_000 {
                        continuation.resume(returning: [:])
                        return
                    }
                    nsAttrStr = highlighter.highlight(highlightContent)
                } else {
                    nsAttrStr = highlighter.highlight(highlightContent, as: lang)
                }

                guard let result = nsAttrStr else {
                    continuation.resume(returning: [:])
                    return
                }

                let resultMap = self.extractColorMap(from: result)
                continuation.resume(returning: resultMap)
            }
        }

        // Only cache non-empty results.
        if !map.isEmpty {
            renderCache.setValue(map, forKey: cacheKey)
        }
        return map
    }

    // MARK: - Appearance Helper

    /// Returns true if the current system appearance is dark.
    /// Safe to call from main thread.
    private func currentAppearanceIsDark() -> Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }

    // MARK: - NSAttributedString → HighlightMap Conversion

    private func extractColorMap(from nsAttrStr: NSAttributedString) -> HighlightMap {
        var map: HighlightMap = [:]

        nsAttrStr.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: nsAttrStr.length)
        ) { value, range, _ in
            guard let color = value as? PlatformColor else { return }
            map[range] = color
        }

        return map
    }
}

// MARK: - HighlightMap Extension

public extension CodeHighlighter.HighlightMap {
    func apply(to content: String, with theme: MarkdownTheme) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing

        let plainTextColor = theme.colors.code
        let attributedContent: NSMutableAttributedString = .init(
            string: content,
            attributes: [
                .font: theme.fonts.code,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: plainTextColor,
            ]
        )

        let length = attributedContent.length
        for (range, color) in self {
            guard range.location >= 0, range.upperBound <= length else { continue }
            guard color != plainTextColor else { continue }
            attributedContent.addAttributes([.foregroundColor: color], range: range)
        }
        return attributedContent
    }

    /// Apply highlights to a **slice** of the full content.
    func apply(toSlice slice: String, charOffset: Int, with theme: MarkdownTheme) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing

        let plainTextColor = theme.colors.code
        let attributedContent: NSMutableAttributedString = .init(
            string: slice,
            attributes: [
                .font: theme.fonts.code,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: plainTextColor,
            ]
        )

        let sliceLength = attributedContent.length
        let sliceEnd = charOffset + sliceLength

        for (range, color) in self {
            guard range.upperBound > charOffset, range.location < sliceEnd else { continue }
            guard color != plainTextColor else { continue }

            let clampedStart = Swift.max(range.location, charOffset)
            let clampedEnd = Swift.min(range.upperBound, sliceEnd)
            let localRange = NSRange(location: clampedStart - charOffset, length: clampedEnd - clampedStart)
            guard localRange.length > 0, localRange.location >= 0, localRange.upperBound <= sliceLength else { continue }

            attributedContent.addAttributes([.foregroundColor: color], range: localRange)
        }
        return attributedContent
    }
}
