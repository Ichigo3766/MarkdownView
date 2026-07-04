import MarkdownParser
import XCTest

final class MathPlaceholderRecoveryTests: XCTestCase {
    func testInlineMathInsideStrongNodeIsRecovered() {
        let markdown = "**Conclusion: shell mass \\\\(M_s\\\\) remains centered.**"
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    func testInlineMathInsideEmphasisNodeIsRecovered() {
        let markdown = "_Inline math \\\\(x+y\\\\) should render._"
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    func testInlineMathInsideStrikethroughNodeIsRecovered() {
        let markdown = "~~Deprecated \\\\(x_0\\\\) notation~~"
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    func testInlineMathInsideLinkLabelIsRecovered() {
        let markdown = "[equation \\\\(E=mc^2\\\\)](https://example.com)"
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    func testInlineMathInsideNestedInlineNodesIsRecovered() {
        let markdown = "_See **\\(a^2+b^2=c^2\\)** for the proof._"
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    func testInlineMathInsideTableCellNestedStrongNodeIsRecovered() {
        let markdown = """
        | Case | Value |
        | --- | --- |
        | A | **\\(M_s\\)** |
        """
        let result = MarkdownParser().parse(markdown)

        XCTAssertFalse(containsMathPlaceholderCode(in: result.document))
        XCTAssertTrue(containsMathNode(in: result.document))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Regression tests: space-free single-backslash delimiters
    // ─────────────────────────────────────────────────────────────────────────

    /// \(x^2\) — no surrounding spaces — must produce a .math node, not raw text.
    func testSingleBackslashInlineNoSpaces() {
        let markdown = "The area is \\(x^2\\) here."
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "\\(x^2\\) should render as math")
    }

    /// \(E=mc^2\) — Einstein's equation without spaces — must render.
    func testSingleBackslashEinsteinNoSpaces() {
        let markdown = "\\(E=mc^2\\)"
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "\\(E=mc^2\\) should render as math")
    }

    /// \(\frac{a}{b}\) — fraction with backslash command — must render.
    func testSingleBackslashFractionNoSpaces() {
        let markdown = "The ratio is \\(\\frac{a}{b}\\)."
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "\\(\\frac{a}{b}\\) should render as math")
    }

    /// \[x^2\] — display math without spaces — must render.
    func testSingleBackslashDisplayNoSpaces() {
        let markdown = "\\[x^2\\]"
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "\\[x^2\\] should render as math")
    }

    /// Multi-line display math \[\n...\n\] — must render.
    func testSingleBackslashDisplayMultiline() {
        let markdown = "\\[\n\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n\\]"
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "multi-line \\[...\\] should render as math")
    }

    /// $x^2 + y^2 = z^2$ — dollar-delimited inline math must render.
    func testDollarInlineMathRenders() {
        let markdown = "Pythagorean theorem: $x^2 + y^2 = z^2$"
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "$x^2 + y^2 = z^2$ should render as math")
    }

    /// $\frac{1}{2}$ — dollar fraction must render.
    func testDollarFractionRenders() {
        let markdown = "Half is $\\frac{1}{2}$."
        let result = MarkdownParser().parse(markdown)
        XCTAssertTrue(containsMathNode(in: result.document), "$\\frac{1}{2}$ should render as math")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Regression tests: currency must NOT be treated as math
    // ─────────────────────────────────────────────────────────────────────────

    /// $50 — plain currency must stay as text.
    func testCurrencySingleDollarNotMath() {
        let markdown = "The item costs $50."
        let result = MarkdownParser().parse(markdown)
        XCTAssertFalse(containsMathNode(in: result.document), "$50 must NOT render as math")
    }

    /// $50-$100 range — must stay as text.
    func testCurrencyRangeNotMath() {
        let markdown = "Prices range from $50 to $100."
        let result = MarkdownParser().parse(markdown)
        XCTAssertFalse(containsMathNode(in: result.document), "$50 to $100 must NOT render as math")
    }

    /// "earn $5 or $10" — two stray dollar amounts must stay as text.
    func testCurrencyTwoDollarAmountsNotMath() {
        let markdown = "You can earn $5 or $10 today."
        let result = MarkdownParser().parse(markdown)
        XCTAssertFalse(containsMathNode(in: result.document), "$5 and $10 must NOT render as math")
    }

    /// $a + b$ — no LaTeX indicator — must stay as text.
    func testPlainDollarNoLatexIndicatorNotMath() {
        let markdown = "The value $a + b$ is just text."
        let result = MarkdownParser().parse(markdown)
        XCTAssertFalse(containsMathNode(in: result.document), "$a + b$ has no LaTeX indicator so must NOT render as math")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Regression test: math inside a fenced code block must NOT render
    // ─────────────────────────────────────────────────────────────────────────

    /// A fenced ```latex block containing \[...\] and $...$ must remain literal.
    func testMathInsideFencedCodeBlockIsLiteral() {
        let markdown = """
        ```latex
        \\[
        ax^2 + bx + c = 0
        \\]
        where $a \\neq 0$.
        ```
        """
        let result = MarkdownParser().parse(markdown)
        // The code block content must be a .codeBlock node, not math
        XCTAssertFalse(containsMathNode(in: result.document), "math inside ```latex``` code block must NOT produce math nodes")
        let hasCodeBlock = result.document.contains { block in
            if case .codeBlock = block { return true }
            return false
        }
        XCTAssertTrue(hasCodeBlock, "fenced latex block should produce a .codeBlock node")
    }
}

private func containsMathPlaceholderCode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            containsMathPlaceholderCode(in: children)
        case let .bulletedList(_, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .numberedList(_, _, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .taskList(_, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            containsMathPlaceholderCode(in: content)
        case let .table(_, rows):
            rows.contains { row in
                row.cells.contains { containsMathPlaceholderCode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            false
        }
    }
}

private func containsMathPlaceholderCode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case let .code(content):
            MarkdownParser.typeForReplacementText(content) == .math
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            containsMathPlaceholderCode(in: children)
        case let .link(_, children), let .image(_, children):
            containsMathPlaceholderCode(in: children)
        default:
            false
        }
    }
}

private func containsMathNode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            containsMathNode(in: children)
        case let .bulletedList(_, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .numberedList(_, _, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .taskList(_, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            containsMathNode(in: content)
        case let .table(_, rows):
            rows.contains { row in
                row.cells.contains { containsMathNode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            false
        }
    }
}

private func containsMathNode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case .math:
            true
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            containsMathNode(in: children)
        case let .link(_, children), let .image(_, children):
            containsMathNode(in: children)
        default:
            false
        }
    }
}
