//
//  MarkdownView+Representable.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import SwiftUI
import UIKit

struct MarkdownViewRepresentable: UIViewRepresentable, MarkdownViewRepresentableBase {
    let contentSource: MarkdownView.ContentSource
    let theme: MarkdownTheme
    var codeBlockAutoScroll: Bool = false
    var codeBlockBarHidden: Bool = false

    func makeUIView(context _: Context) -> MarkdownTextView {
        createMarkdownTextView()
    }

    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        updateMarkdownTextView(uiView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> MarkdownViewCoordinator {
        MarkdownViewCoordinator()
    }

    /// Called synchronously by SwiftUI during its layout pass.
    /// Returns the intrinsic height of the rendered markdown for the proposed width.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MarkdownTextView,
        context: Context
    ) -> CGSize? {
        let fallbackWidth = uiView.window?.bounds.width
            ?? uiView.superview?.bounds.width
            ?? 390
        let width = proposal.width ?? fallbackWidth
        guard width > 0 else { return nil }
        let size = uiView.boundingSize(for: width)
        let height = ceil(size.height)
        guard height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
