//
//  MarkdownView+Representable.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import SwiftUI

#if canImport(UIKit)
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
        /// Returns the intrinsic height of the rendered markdown for the proposed width,
        /// eliminating the need for @State measuredHeight + DispatchQueue.main.async writes
        /// (which caused AttributeGraph cycle warnings on every update).
        func sizeThatFits(
            _ proposal: ProposedViewSize,
            uiView: MarkdownTextView,
            context: Context
        ) -> CGSize? {
            // Prefer the actual window/superview width over UIScreen.main.bounds.width.
            // UIScreen.main reports the physical screen width, which is wrong in Split View,
            // Slide Over, and Stage Manager where the app window is narrower than the screen.
            let fallbackWidth = uiView.window?.bounds.width
                ?? uiView.superview?.bounds.width
                ?? 390  // safe iPhone default; real width will arrive on next layout pass
            let width = proposal.width ?? fallbackWidth
            guard width > 0 else { return nil }
            let size = uiView.boundingSize(for: width)
            let height = ceil(size.height)
            guard height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
    }

#elseif canImport(AppKit)
    import AppKit

    struct MarkdownViewRepresentable: NSViewRepresentable, MarkdownViewRepresentableBase {
        let contentSource: MarkdownView.ContentSource
        let theme: MarkdownTheme

        func makeNSView(context _: Context) -> MarkdownTextView {
            createMarkdownTextView()
        }

        func updateNSView(_ nsView: MarkdownTextView, context: Context) {
            updateMarkdownTextView(nsView, coordinator: context.coordinator)
        }

        func makeCoordinator() -> MarkdownViewCoordinator {
            MarkdownViewCoordinator()
        }
    }
#endif
