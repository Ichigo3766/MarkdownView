import Foundation

public enum MarkdownBlockNode: Hashable, Equatable, Codable {
    case blockquote(children: [MarkdownBlockNode])
    case callout(kind: CalloutKind, children: [MarkdownBlockNode])
    case bulletedList(isTight: Bool, items: [RawListItem])
    case numberedList(isTight: Bool, start: Int, items: [RawListItem])
    case taskList(isTight: Bool, items: [RawTaskListItem])
    case codeBlock(fenceInfo: String?, content: String)
//    case htmlBlock(content: String)
    case paragraph(content: [MarkdownInlineNode])
    case heading(level: Int, content: [MarkdownInlineNode])
    case table(columnAlignments: [RawTableColumnAlignment], rows: [RawTableRow])
    case thematicBreak
}

/// GitHub-style alert/callout kinds (`> [!NOTE]`, `> [!WARNING]`, etc.).
public enum CalloutKind: String, Hashable, Equatable, Codable, Sendable {
    case note
    case tip
    case important
    case warning
    case caution

    /// Parses the bracketed marker text (case-insensitive), e.g. "[!NOTE]".
    public init?(marker: String) {
        let trimmed = marker.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]") else { return nil }
        let inner = String(trimmed.dropFirst(2).dropLast())
        switch inner {
        case "note": self = .note
        case "tip": self = .tip
        case "important": self = .important
        case "warning": self = .warning
        case "caution": self = .caution
        default: return nil
        }
    }

    /// SF Symbol name for the callout icon.
    public var systemImageName: String {
        switch self {
        case .note: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .important: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .caution: "exclamationmark.octagon.fill"
        }
    }

    /// Display title shown at the top of the callout.
    public var title: String {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }
}


public extension MarkdownBlockNode {
    var children: [MarkdownBlockNode] {
        switch self {
        case let .blockquote(children):
            children
        case let .bulletedList(_, items):
            items.map(\.children).flatMap(\.self)
        case let .numberedList(_, _, items):
            items.map(\.children).flatMap(\.self)
        case let .taskList(_, items):
            items.map(\.children).flatMap(\.self)
        default:
            []
        }
    }

    var isParagraph: Bool {
        guard case .paragraph = self else { return false }
        return true
    }
}

public struct RawListItem: Hashable, Equatable, Codable {
    public let children: [MarkdownBlockNode]

    public init(children: [MarkdownBlockNode]) {
        self.children = children
    }
}

public struct RawTaskListItem: Hashable, Equatable, Codable {
    public let isCompleted: Bool
    public let children: [MarkdownBlockNode]

    public init(isCompleted: Bool, children: [MarkdownBlockNode]) {
        self.isCompleted = isCompleted
        self.children = children
    }
}

public enum RawTableColumnAlignment: Character, Equatable, Codable {
    case none = "\0"
    case left = "l"
    case center = "c"
    case right = "r"
}

public struct RawTableRow: Hashable, Equatable, Codable {
    public let cells: [RawTableCell]

    public init(cells: [RawTableCell]) {
        self.cells = cells
    }
}

public struct RawTableCell: Hashable, Equatable, Codable {
    public let content: [MarkdownInlineNode]

    public init(content: [MarkdownInlineNode]) {
        self.content = content
    }
}
