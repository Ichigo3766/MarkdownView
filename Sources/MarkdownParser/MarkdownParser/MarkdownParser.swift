//
//  MarkdownParser.swift
//  FlowMarkdownView
//
//  Created by 秋星桥 on 2025/1/2.
//

import cmark_gfm
import cmark_gfm_extensions
import Foundation

public final class MarkdownParser: Sendable {
    public init() {}

    func withParser<T>(_ block: (UnsafeMutablePointer<cmark_parser>) -> T) -> T {
        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)!
        cmark_gfm_core_extensions_ensure_registered()
        let extensionNames = [
            "autolink",
            "strikethrough",
            "tagfilter",
            "tasklist",
            "table",
        ]
        for extensionName in extensionNames {
            guard let syntaxExtension = cmark_find_syntax_extension(extensionName) else {
                assertionFailure()
                continue
            }
            cmark_parser_attach_syntax_extension(parser, syntaxExtension)
        }
        defer { cmark_parser_free(parser) }
        return block(parser)
    }

    public struct ParseResult: @unchecked Sendable {
        public let document: [MarkdownBlockNode]
        public let mathContext: [Int: String]
    }

    public func parse(_ markdown: String) -> ParseResult {
        let math = MathContext(preprocessText: markdown)
        math.process()
        let markdown = math.indexedContent ?? markdown
        let nodes = withParser { parser in
            markdown.withCString { str in
                cmark_parser_feed(parser, str, strlen(str))
                return cmark_parser_finish(parser)
            }
        }
        var blocks = dumpBlocks(root: nodes)
        blocks = finalizeMathBlocks(blocks, mathContext: math)
        return .init(document: blocks, mathContext: math.contents)
    }
}
