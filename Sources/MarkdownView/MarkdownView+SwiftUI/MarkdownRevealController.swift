//
//  MarkdownRevealController.swift
//  MarkdownView
//
//  Lets a host drive the draw-time reveal of a MarkdownView every display frame
//  without going through SwiftUI state, so no view body is re-evaluated per frame.
//

import UIKit

@MainActor
public final class MarkdownRevealController {
    private weak var view: MarkdownTextView?
    private var progress: Double?
    private var fadeCharacters: CGFloat = 0
    /// Set when the next content is a different block: the value must not be
    /// shown on the view's current text, only once the new text is attached.
    private var pending = false

    public init() {}

    /// Reveals the first `progress` (0...1) share of the attached view's text;
    /// `nil` shows all. Applied immediately.
    public func update(progress: Double?, fadeCharacters: CGFloat) {
        self.progress = progress
        self.fadeCharacters = fadeCharacters
        guard !pending else { return }
        view?.setReveal(progress: progress, fadeCharacters: fadeCharacters)
    }

    /// Stores a reveal for content that is about to replace the attached view's
    /// text. It is applied when SwiftUI next updates the view.
    public func stage(progress: Double?, fadeCharacters: CGFloat) {
        self.progress = progress
        self.fadeCharacters = fadeCharacters
        pending = true
    }

    func attach(_ newView: MarkdownTextView) {
        guard view !== newView || pending else { return }
        if view !== newView {
            // The previous view is no longer being typed: show it in full.
            view?.setReveal(progress: nil, fadeCharacters: 0)
            view = newView
        }
        pending = false
        newView.setReveal(progress: progress, fadeCharacters: fadeCharacters)
    }
}
