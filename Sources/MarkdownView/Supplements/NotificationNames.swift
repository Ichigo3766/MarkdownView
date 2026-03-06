//
//  NotificationNames.swift
//  MarkdownView
//

import Foundation

public extension Notification.Name {
    /// Posted when the user taps the "eye" (preview) button on a code block.
    /// `userInfo` contains:
    /// - `"code"`: `String` — the full code content
    /// - `"language"`: `String` — the language tag (e.g., "python", "swift")
    static let markdownCodePreview = Notification.Name("markdownCodePreview")
}
