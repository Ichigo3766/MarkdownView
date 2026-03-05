//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import HighlightSwift
import LRUCache

#if canImport(UIKit)
    import UIKit

    public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
    import AppKit

    public typealias PlatformColor = NSColor
#endif

public final class CodeHighlighter: @unchecked Sendable {
    public typealias HighlightMap = [NSRange: PlatformColor]

    public private(set) var renderCache = LRUCache<Int, HighlightMap>(countLimit: 256)
    private let highlight = Highlight()

    private init() {}

    public static let current = CodeHighlighter()

    // MARK: - Key Generation

    public func key(for content: String, language: String?) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(language?.lowercased() ?? "")
        return hasher.finalize()
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
        let key = key ?? self.key(for: content, language: language)
        if let cached = renderCache.value(forKey: key) {
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
        let cacheKey = key(for: content, language: language)

        // Check cache first
        if let cached = renderCache.value(forKey: cacheKey) {
            return cached
        }

        do {
            let lang = language?.lowercased() ?? ""
            let attributedText: AttributedString

            // Use dark-mode-aware colors — HighlightSwift auto-switches
            let colors: HighlightColors = .dark(.github)

            if lang.isEmpty || lang == "plaintext" {
                // Auto-detect language
                attributedText = try await highlight.attributedText(content, colors: colors)
            } else {
                // Use language string directly — HighlightSwift accepts
                // language aliases like "swift", "python", "javascript", etc.
                attributedText = try await highlight.attributedText(content, language: lang, colors: colors)
            }

            // Convert AttributedString → [NSRange: PlatformColor]
            let map = extractColorMap(from: attributedText)
            renderCache.setValue(map, forKey: cacheKey)
            return map
        } catch {
            return [:]
        }
    }

    // MARK: - AttributedString → HighlightMap Conversion

    private func extractColorMap(from attributedText: AttributedString) -> HighlightMap {
        var map: HighlightMap = [:]
        let nsAttrStr = NSAttributedString(attributedText)

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
}
