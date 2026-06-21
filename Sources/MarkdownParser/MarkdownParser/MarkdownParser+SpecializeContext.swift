//
//  MarkdownParser+SpecializeContext.swift
//  MarkdownView
//
//  Created by 秋星桥 on 5/27/25.
//

import cmark_gfm
import cmark_gfm_extensions
import Foundation

extension MarkdownParser {
    class SpecializeContext {
        private var context: [MarkdownBlockNode] = []

        init() {}

        func append(_ node: MarkdownBlockNode) {
            processNode(node)
        }

        func complete() -> [MarkdownBlockNode] {
            defer { context.removeAll() }
            return context
        }
    }
}

private extension MarkdownParser.SpecializeContext {
    typealias ProcessedListItem<Item> = (item: Item, picks: [MarkdownBlockNode])

    func rawListItemByCherryPick(
        _ rawListItem: RawListItem
    ) -> (RawListItem, [MarkdownBlockNode]) {
        let (children, pickedNodes) = cherryPickChildren(rawListItem.children)
        return (RawListItem(children: children), pickedNodes)
    }

    func rawTaskListItemByCherryPick(
        _ rawTaskListItem: RawTaskListItem
    ) -> (RawTaskListItem, [MarkdownBlockNode]) {
        let (children, pickedNodes) = cherryPickChildren(rawTaskListItem.children)
        return (
            RawTaskListItem(isCompleted: rawTaskListItem.isCompleted, children: children),
            pickedNodes
        )
    }

    func processNodeInsideListEnvironment(
        _ node: MarkdownBlockNode
    ) -> [MarkdownBlockNode] {
        switch node {
        case let .bulletedList(isTight, items):
            let processedItems = processItems(items, using: rawListItemByCherryPick)
            return buildBlocks(from: processedItems) { processedItems in
                .bulletedList(isTight: isTight, items: processedItems)
            }
        case let .numberedList(isTight, start, items):
            let processedItems = processItems(items, using: rawListItemByCherryPick)
            let containsExtractedNodes = processedItems.contains { !$0.picks.isEmpty }
            let builder: ([RawListItem]) -> MarkdownBlockNode = containsExtractedNodes
                ? { .bulletedList(isTight: isTight, items: $0) }
                : { .numberedList(isTight: isTight, start: start, items: $0) }
            return buildBlocks(from: processedItems, using: builder)
        case let .taskList(isTight, items):
            let processedItems = processItems(items, using: rawTaskListItemByCherryPick)
            return buildBlocks(from: processedItems) { processedItems in
                .taskList(isTight: isTight, items: processedItems)
            }
        default:
            assertionFailure("unsupported node type in list environment")
            return []
        }
    }

    func cherryPickChildren(
        _ children: [MarkdownBlockNode]
    ) -> ([MarkdownBlockNode], [MarkdownBlockNode]) {
        var sanitizedChildren: [MarkdownBlockNode] = []
        var pickedNodes: [MarkdownBlockNode] = []

        for child in children {
            switch child {
            case .codeBlock, .table, .heading, .thematicBreak, .blockquote:
                pickedNodes.append(child)
            case let .bulletedList(isTight, items):
                let processedItems = processItems(items, using: rawListItemByCherryPick)
                sanitizedChildren.append(.bulletedList(isTight: isTight, items: processedItems.map(\.item)))
                pickedNodes.append(contentsOf: processedItems.flatMap(\.picks))
            case let .numberedList(isTight, start, items):
                let processedItems = processItems(items, using: rawListItemByCherryPick)
                sanitizedChildren.append(.numberedList(isTight: isTight, start: start, items: processedItems.map(\.item)))
                pickedNodes.append(contentsOf: processedItems.flatMap(\.picks))
            case let .taskList(isTight, items):
                let processedItems = processItems(items, using: rawTaskListItemByCherryPick)
                sanitizedChildren.append(.taskList(isTight: isTight, items: processedItems.map(\.item)))
                pickedNodes.append(contentsOf: processedItems.flatMap(\.picks))
            default:
                sanitizedChildren.append(child)
            }
        }

        return (sanitizedChildren, pickedNodes)
    }

    func processItems<Item>(
        _ items: [Item],
        using processor: (Item) -> (Item, [MarkdownBlockNode])
    ) -> [ProcessedListItem<Item>] {
        items.map { item in
            let (processedItem, pickedNodes) = processor(item)
            return (item: processedItem, picks: pickedNodes)
        }
    }

    func buildBlocks<Item>(
        from processedItems: [ProcessedListItem<Item>],
        using makeList: ([Item]) -> MarkdownBlockNode
    ) -> [MarkdownBlockNode] {
        guard !processedItems.isEmpty else { return [] }

        var result: [MarkdownBlockNode] = []
        var currentItems: [Item] = []

        for (index, element) in processedItems.enumerated() {
            currentItems.append(element.item)

            if !element.picks.isEmpty {
                if !currentItems.isEmpty {
                    result.append(makeList(currentItems))
                    currentItems.removeAll(keepingCapacity: true)
                }
                result.append(contentsOf: element.picks)
            } else if index == processedItems.count - 1, !currentItems.isEmpty {
                result.append(makeList(currentItems))
            }
        }

        return result
    }

    func processNode(_ node: MarkdownBlockNode) {
        switch node {
        case let .blockquote(children):
            // Detect GitHub-style callouts: a blockquote whose first paragraph
            // begins with a `[!TYPE]` marker line.
            if let (kind, strippedChildren) = detectCallout(children) {
                let flattened = flattenBlockquoteChildren(strippedChildren)
                context.append(.callout(kind: kind, children: flattened))
            } else {
                let flattenedChildren = flattenBlockquoteChildren(children)
                context.append(.blockquote(children: flattenedChildren))
            }
        case .bulletedList:
            let nodes = processNodeInsideListEnvironment(node)
            context.append(contentsOf: nodes)
        case .numberedList:
            let nodes = processNodeInsideListEnvironment(node)
            context.append(contentsOf: nodes)
        case .taskList:
            let nodes = processNodeInsideListEnvironment(node)
            context.append(contentsOf: nodes)
        case let .codeBlock(fenceInfo, content):
            context.append(.codeBlock(fenceInfo: fenceInfo, content: content))
        case let .paragraph(content):
            context.append(.paragraph(content: content))
        case let .heading(level, content):
            context.append(.heading(level: level, content: content))
        case let .table(columnAlignments, rows):
            context.append(.table(columnAlignments: columnAlignments, rows: rows))
        case let .callout(kind, children):
            // A callout that arrives here directly (rare) is preserved as-is.
            context.append(.callout(kind: kind, children: children))
        case .thematicBreak:
            context.append(.thematicBreak)
        }
    }

    /// Detects a GitHub-style callout marker (`[!NOTE]`, `[!WARNING]`, …) at the
    /// start of a blockquote's first paragraph. Returns the callout kind plus
    /// the children with the marker line removed, or nil if not a callout.
    func detectCallout(
        _ children: [MarkdownBlockNode]
    ) -> (CalloutKind, [MarkdownBlockNode])? {
        guard let first = children.first,
              case let .paragraph(content) = first,
              case let .text(firstText)? = content.first
        else { return nil }

        // The marker must be on its own line at the very start, e.g. "[!NOTE]\n…"
        // cmark keeps the marker + following soft break inside the same paragraph.
        let lines = firstText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let markerLine = lines.first,
              let kind = CalloutKind(marker: String(markerLine))
        else { return nil }

        // Rebuild the first paragraph without the marker line.
        var newFirstContent = content
        let remainder = lines.count > 1 ? String(lines[1]) : ""
        if remainder.isEmpty {
            // Marker consumed the whole first text node — drop it. If that leaves
            // the paragraph's remaining inlines starting with a soft break, drop it.
            newFirstContent.removeFirst()
            if case .softBreak = newFirstContent.first {
                newFirstContent.removeFirst()
            }
        } else {
            newFirstContent[0] = .text(remainder)
        }

        var newChildren = children
        if newFirstContent.isEmpty {
            newChildren.removeFirst()
        } else {
            newChildren[0] = .paragraph(content: newFirstContent)
        }
        return (kind, newChildren)
    }

    func flattenBlockquoteChildren(_ children: [MarkdownBlockNode]) -> [MarkdownBlockNode] {
        var flattenedChildren: [MarkdownBlockNode] = []

        for child in children {
            switch child {
            case let .paragraph(content):
                flattenedChildren.append(.paragraph(content: content))
            case let .heading(_, content):
                flattenedChildren.append(.paragraph(content: content))
            case let .codeBlock(_, content):
                flattenedChildren.append(.paragraph(content: [.text(content)]))
            case let .blockquote(nestedChildren):
                flattenedChildren.append(contentsOf: flattenBlockquoteChildren(nestedChildren))
            case let .callout(_, nestedChildren):
                flattenedChildren.append(contentsOf: flattenBlockquoteChildren(nestedChildren))
            case let .bulletedList(_, items):
                flattenedChildren.append(contentsOf: extractParagraphs(from: items))
            case let .numberedList(_, _, items):
                flattenedChildren.append(contentsOf: extractParagraphs(from: items))
            case let .taskList(_, items):
                flattenedChildren.append(contentsOf: extractParagraphs(from: items))
            case let .table(_, rows):
                for row in rows {
                    flattenedChildren.append(contentsOf: row.cells.map { .paragraph(content: $0.content) })
                }
            case .thematicBreak:
                continue
            }
        }

        return flattenedChildren
    }

    func extractParagraphsFromListItem(_ children: [MarkdownBlockNode]) -> [MarkdownBlockNode] {
        var paragraphs: [MarkdownBlockNode] = []

        for child in children {
            switch child {
            case let .paragraph(content):
                paragraphs.append(.paragraph(content: content))
            case let .heading(_, content):
                paragraphs.append(.paragraph(content: content))
            case let .codeBlock(_, content):
                paragraphs.append(.paragraph(content: [.text(content)]))
            case .blockquote:
                // blockquote 应该已经被提取到顶级，这里不应该出现
                assertionFailure("blockquote should not appear in list items")
            case let .bulletedList(_, items):
                paragraphs.append(contentsOf: extractParagraphs(from: items))
            case let .numberedList(_, _, items):
                paragraphs.append(contentsOf: extractParagraphs(from: items))
            case let .taskList(_, items):
                paragraphs.append(contentsOf: extractParagraphs(from: items))
            default:
                continue
            }
        }

        return paragraphs
    }

    func extractParagraphs(from items: [RawListItem]) -> [MarkdownBlockNode] {
        items.flatMap { extractParagraphsFromListItem($0.children) }
    }

    func extractParagraphs(from items: [RawTaskListItem]) -> [MarkdownBlockNode] {
        items.flatMap { extractParagraphsFromListItem($0.children) }
    }
}
