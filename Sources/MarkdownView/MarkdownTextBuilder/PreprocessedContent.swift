//
//  PreprocessedContent.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/5/25.
//

import Foundation
import MarkdownParser

public extension MarkdownTextView {
    final class PreprocessedContent {
        public let blocks: [MarkdownBlockNode]
        /// Math render map — mutable so the async math-render pass can populate it
        /// without rebuilding the entire PreprocessedContent object.
        public var rendered: RenderedTextContent.Map
        public let highlightMaps: [Int: CodeHighlighter.HighlightMap]

        /// Raw LaTeX strings keyed by equation index, carried from the parse result.
        /// Used by the async render pass to produce images off the main thread.
        public let mathContext: [Int: String]

        public init(
            blocks: [MarkdownBlockNode],
            rendered: RenderedTextContent.Map,
            highlightMaps: [Int: CodeHighlighter.HighlightMap]
        ) {
            self.blocks = blocks
            self.rendered = rendered
            self.highlightMaps = highlightMaps
            self.mathContext = [:]
        }

        /// Fast init: parses but does NOT render math images.
        /// The caller should fire `renderMathAsync(theme:)` to fill `rendered` off-thread.
        public init(parserResultNoMath parserResult: MarkdownParser.ParseResult) {
            blocks = parserResult.document
            rendered = [:]
            highlightMaps = [:]
            mathContext = parserResult.mathContext
        }

        public init(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme) {
            blocks = parserResult.document
            rendered = parserResult.render(theme: theme)
            highlightMaps = [:]
            mathContext = parserResult.mathContext
        }

        public init() {
            blocks = .init()
            rendered = .init()
            highlightMaps = .init()
            mathContext = [:]
        }

        /// True when there are equations that have not yet been rendered to images.
        public var hasPendingMath: Bool {
            !mathContext.isEmpty && rendered.isEmpty
        }

        /// Renders all equations to images on a background thread.
        /// Merges results into `self.rendered` and calls `completion` on the main actor.
        public func renderMathAsync(theme: MarkdownTheme, completion: @escaping @MainActor () -> Void) {
            guard hasPendingMath else {
                Task { @MainActor in completion() }
                return
            }
            let contextSnapshot = mathContext
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                var map: RenderedTextContent.Map = [:]
                for (key, value) in contextSnapshot {
                    guard !Task.isCancelled else { return }
                    var image = MathRenderer.renderToImage(
                        latex: value,
                        fontSize: theme.fonts.body.pointSize,
                        textColor: theme.colors.body
                    )
                    #if canImport(UIKit)
                    image = image?.withRenderingMode(.alwaysTemplate)
                    #endif
                    let replacementText = MarkdownParser.replacementText(for: .math, identifier: .init(key))
                    map[replacementText] = RenderedTextContent(image: image, text: value)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.rendered = map
                    completion()
                }
            }
        }
    }
}

public extension MarkdownParser.ParseResult {
    fileprivate func renderMathContent(_ theme: MarkdownTheme, _ renderedContexts: inout [String: RenderedTextContent]) {
        for (key, value) in mathContext {
            var image = MathRenderer.renderToImage(
                latex: value,
                fontSize: theme.fonts.body.pointSize,
                textColor: theme.colors.body
            )
            #if canImport(UIKit)
                image = image?.withRenderingMode(.alwaysTemplate)
            #endif
            let renderedContext = RenderedTextContent(
                image: image,
                text: value
            )
            let replacementText = MarkdownParser.replacementText(for: .math, identifier: .init(key))
            renderedContexts[replacementText] = renderedContext
        }
    }

    func render(theme: MarkdownTheme) -> RenderedTextContent.Map {
        var renderedContexts: [String: RenderedTextContent] = [:]
        renderMathContent(theme, &renderedContexts)
        return renderedContexts
    }
}

public extension MarkdownParser.ParseResult {
    fileprivate func renderHighlighMap(_: MarkdownTheme, highlightMaps: inout [Int: CodeHighlighter.HighlightMap]) {
        var iterator: [Any] = document
        while !iterator.isEmpty {
            let node = iterator.removeFirst()
            if let node = node as? MarkdownBlockNode {
                iterator.append(contentsOf: node.children)
                switch node {
                case let .blockquote(children):
                    iterator.append(contentsOf: children)
                case let .bulletedList(_, items):
                    iterator.append(contentsOf: items.flatMap(\.children))
                case let .numberedList(_, _, items):
                    iterator.append(contentsOf: items.flatMap(\.children))
                case let .taskList(_, items):
                    iterator.append(contentsOf: items.flatMap(\.children))
                case let .codeBlock(fenceInfo, content):
                    let key = CodeHighlighter.current.key(for: content, language: fenceInfo)
                    let map = CodeHighlighter.current.highlight(key: key, content: content, language: fenceInfo)
                    highlightMaps[key] = map
                case let .paragraph(content):
                    iterator.append(contentsOf: content)
                case let .heading(_, content):
                    iterator.append(contentsOf: content)
                case let .table(_, rows):
                    iterator.append(contentsOf: rows.flatMap(\.cells).map(\.content))
                case .thematicBreak:
                    break
                }
                continue
            }
            if let node = node as? MarkdownInlineNode {
                switch node {
                // 用户说这里很乱 不要高亮了
                // case let .code(string), let .html(string):
                // let key = CodeHighlighter.current.key(for: string, language: "")
                // let map = CodeHighlighter.current.highlight(key: key, content: string, language: "")
                // highlightMaps[key] = map
                default:
                    break
                }
                continue
            }
            continue
        }
    }

    func render(theme: MarkdownTheme) -> [Int: CodeHighlighter.HighlightMap] {
        var highlightMap = [Int: CodeHighlighter.HighlightMap]()
        renderHighlighMap(theme, highlightMaps: &highlightMap)
        return highlightMap
    }
}
