//
//  MarkdownParser+MathContext.swift
//  MarkdownView
//
//  Created by 秋星桥 on 6/3/25.
//

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PRE-CMARK math pattern
//
// Runs over the raw markdown string *before* CommonMark sees it.  Every match
// is replaced by an opaque placeholder token so cmark never touches the LaTeX
// (backslashes are otherwise consumed/escaped by cmark).
//
// Pattern ordering: most-specific first so that `$$` wins over `$` and
// double-backslash `\\[` wins over single `\[`.
//
// CURRENCY SAFETY: the bare `$...$` pattern requires at least one LaTeX
// indicator character inside (backslash, ^, _, or {).  This means:
//   MATCHED  → $x^2$  $\alpha$  $\frac{a}{b}$  $x_{i}$  $2^{10}$
//   IGNORED  → $50   $100   $5.99   $a + b   "earn $5 or $10"
// ─────────────────────────────────────────────────────────────────────────────
private let mathPattern: NSRegularExpression? = {
    let patterns = [
        // 1. Display math:  $$ ... $$
        ###"\$\$([\s\S]*?)\$\$"###,

        // 2. Display math:  \\[ ... \\]  (double-backslash, already-escaped form)
        ###"\\\\\[([\s\S]*?)\\\\\]"###,

        // 3. Inline math:   \\( ... \\)  (double-backslash, already-escaped form)
        ###"\\\\\(([\s\S]*?)\\\\\)"###,

        // 4. Display math:  \[ ... \]  (single backslash; spaces NOT required)
        ###"\\\[([\s\S]*?)\\\]"###,

        // 5. Inline math:   \( ... \)  (single backslash; spaces NOT required)
        //    [^\r\n]*? keeps it on one line so we never swallow a closing
        //    parenthesis from unrelated prose across a paragraph break.
        ###"\\\(([^\r\n]*?)\\\)"###,

        // 6. Inline math:   $...$
        //    Negative lookahead/lookbehind prevents matching $$ (display).
        //    Lookahead requires at least one of  \ ^ _ {  inside the span
        //    to guard against currency values like $50, $100, $a+b.
        "(?<!\\$)\\$(?!\\$)((?=[^\\r\\n\\$]*[\\\\^_{])[^\\r\\n\\$`]+?)(?<!\\$)\\$(?!\\$)",
    ]
    let pattern = patterns.joined(separator: "|")
    guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive]
        // NOTE: Do NOT add .allowCommentsAndWhitespace — that would break the
        // patterns that rely on literal whitespace.
    ) else {
        assertionFailure("failed to create regex for math pattern")
        return nil
    }
    return regex
}()

private struct MathMatch {
    let range: NSRange
    let content: String
    let source: String
}

private func extractMathMatches(in text: String, using regex: NSRegularExpression) -> [MathMatch] {
    let nsText = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
        for rangeIndex in 1 ..< match.numberOfRanges {
            let captureRange = match.range(at: rangeIndex)
            guard captureRange.location != NSNotFound else { continue }
            return MathMatch(
                range: match.range(at: 0),
                content: nsText.substring(with: captureRange),
                source: nsText.substring(with: match.range(at: 0))
            )
        }
        return nil
    }
}

public extension MarkdownParser {
    final class MathContext {
        private let document: String
        private(set) var indexedContent: String?
        private var sourceContents: [Int: String] = [:]

        public fileprivate(set) var contents: [Int: String] = [:]

        init(preprocessText: String) {
            document = preprocessText
        }

        func process() {
            guard let regex = mathPattern else {
                assertionFailure()
                return
            }

        var document = document
        let matches = extractMathMatches(in: document, using: regex).reversed()
        if matches.isEmpty { return }

        for match in matches {
            guard let fullRange = Range(match.range, in: document) else { continue }
            let replacement = register(content: match.content, source: match.source)
            document.replaceSubrange(fullRange, with: replacement)
        }

        indexedContent = document
        }

        func register(content: String, source: String? = nil) -> String {
            let identifier = contents.count
            contents[identifier] = content
            sourceContents[identifier] = source
            return MarkdownParser.replacementText(for: .math, identifier: String(identifier))
        }

        func inlineNode(forReplacementText text: String) -> MarkdownInlineNode? {
            guard MarkdownParser.typeForReplacementText(text) == .math,
                  let identifier = MarkdownParser.identifierForReplacementText(text),
                  let value = Int(identifier),
                  let content = contents[value]
            else {
                return nil
            }
            return .math(
                content: content,
                replacementIdentifier: MarkdownParser.replacementText(
                    for: .math,
                    identifier: identifier
                )
            )
        }

        func restore(content: String) -> String {
            contents.sorted(by: { $0.key < $1.key }).reduce(into: content) { partialResult, element in
                let placeholder = MarkdownParser.replacementText(for: .math, identifier: .init(element.key))
                let source = sourceContents[element.key] ?? element.value
                partialResult = partialResult.replacingOccurrences(of: placeholder, with: source)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST-CMARK (within-block) math pattern
//
// Applied to `.text` nodes that survived CommonMark parsing without being
// converted to a replacement placeholder.  This is a fallback for cases where
// the pre-cmark pass didn't see the span (e.g. content reconstructed from
// emphasis or strong children, or math expressions cmark decoded differently).
//
// Same currency safety rule as above.
// ─────────────────────────────────────────────────────────────────────────────
private let mathPatternWithinBlock: NSRegularExpression? = {
    let patterns = [
        // \( ... \) inline — single backslash, no space requirement
        ###"\\\(([^\r\n]*?)\\\)"###,

        // $...$ guarded inline — must contain a LaTeX indicator
        "\\$(?=[^\\r\\n\\$]*[\\\\^_{])((?:[^\\r\\n\\$`]|\\\\.)+?)\\$",
    ]
    let pattern = patterns.joined(separator: "|")
    guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive]
    ) else {
        assertionFailure("failed to create regex for math pattern")
        return nil
    }
    return regex
}()

extension MarkdownParser {
    func finalizeMathBlocks(_ nodes: [MarkdownBlockNode], mathContext: MathContext) -> [MarkdownBlockNode] {
        nodes.map { finalizeMathBlocks($0, mathContext: mathContext) }.flatMap(\.self)
    }

    func finalizeMathBlocks(_ node: MarkdownBlockNode, mathContext: MathContext) -> [MarkdownBlockNode] {
        switch node {
        case let .blockquote(children):
            return [.blockquote(children: finalizeMathBlocks(children, mathContext: mathContext))]
        case let .callout(kind, children):
            return [.callout(kind: kind, children: finalizeMathBlocks(children, mathContext: mathContext))]
        case let .bulletedList(isTight, items):
            let processedItems = items.map { item in
                RawListItem(children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.bulletedList(isTight: isTight, items: processedItems)]
        case let .numberedList(isTight, start, items):
            let processedItems = items.map { item in
                RawListItem(children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.numberedList(isTight: isTight, start: start, items: processedItems)]
        case let .taskList(isTight, items):
            let processedItems = items.map { item in
                RawTaskListItem(isCompleted: item.isCompleted, children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.taskList(isTight: isTight, items: processedItems)]
        case let .paragraph(content):
            let processedContent = finalizeInlineMathInNodes(content, mathContext: mathContext)
            return [.paragraph(content: processedContent)]
        case let .table(columnAlignments, rows):
            let processedRows = rows.map { row in
                let processedCells = row.cells.map { cell in
                    RawTableCell(content: finalizeInlineMathInNodes(cell.content, mathContext: mathContext))
                }
                return RawTableRow(cells: processedCells)
            }
            return [.table(columnAlignments: columnAlignments, rows: processedRows)]
        case let .codeBlock(language, content):
            // restore replacement content in code blocks if found, we dont want bad links in code blocks
            return [.codeBlock(fenceInfo: language, content: mathContext.restore(content: content))]
        case let .heading(level: level, content: content):
            return [.heading(level: level, content: finalizeInlineMathInNodes(content, mathContext: mathContext))]
        default:
            return [node]
        }
    }

    private func finalizeInlineMathInNodes(_ nodes: [MarkdownInlineNode], mathContext: MathContext) -> [MarkdownInlineNode] {
        var result: [MarkdownInlineNode] = []

        for node in nodes {
            switch node {
            case let .text(text):
                result.append(contentsOf: processInlineMath(text, mathContext: mathContext))
            case let .code(content):
                if let mathNode = mathContext.inlineNode(forReplacementText: content) {
                    result.append(mathNode)
                } else {
                    result.append(node)
                }
            case let .emphasis(children):
                result.append(.emphasis(children: finalizeInlineMathInNodes(children, mathContext: mathContext)))
            case let .strong(children):
                result.append(.strong(children: finalizeInlineMathInNodes(children, mathContext: mathContext)))
            case let .strikethrough(children):
                result.append(.strikethrough(children: finalizeInlineMathInNodes(children, mathContext: mathContext)))
            case let .link(destination, children):
                result.append(.link(destination: destination, children: finalizeInlineMathInNodes(children, mathContext: mathContext)))
            case let .image(source, children):
                result.append(.image(source: source, children: finalizeInlineMathInNodes(children, mathContext: mathContext)))
            default:
                result.append(node)
            }
        }

        return result
    }

    private func processInlineMath(_ text: String, mathContext: MathContext) -> [MarkdownInlineNode] {
        guard let regex = mathPatternWithinBlock else { return [.text(text)] }
        let matches = extractMathMatches(in: text, using: regex)
        if matches.isEmpty { return [.text(text)] }

        let nsText = text as NSString
        var result: [MarkdownInlineNode] = []
        var lastEnd = 0

        for match in matches {
            if match.range.location > lastEnd {
                let beforeText = nsText.substring(
                    with: NSRange(location: lastEnd, length: match.range.location - lastEnd)
                )
                if !beforeText.isEmpty { result.append(.text(beforeText)) }
            }

            result.append(
                .math(
                    content: match.content,
                    replacementIdentifier: mathContext.register(content: match.content)
                )
            )

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            let remainingText = nsText.substring(from: lastEnd)
            if !remainingText.isEmpty {
                result.append(.text(remainingText))
            }
        }

        return result
    }
}
