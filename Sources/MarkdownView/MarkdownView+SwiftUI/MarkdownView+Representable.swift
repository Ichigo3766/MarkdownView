//
//  MarkdownView+Representable.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2026/2/1.
//

import SwiftUI
import os.log

private let markdownUpdateLog = OSLog(subsystem: "com.openui.openui", category: "MarkdownUpdate")

#if canImport(UIKit)
    import UIKit

    struct MarkdownViewRepresentable: UIViewRepresentable, MarkdownViewRepresentableBase {
        let contentSource: MarkdownView.ContentSource
        let theme: MarkdownTheme
        var codeBlockAutoScroll: Bool = false
        var codeBlockBarHidden: Bool = false
        let width: CGFloat
        @Binding var measuredHeight: CGFloat

        var heightBinding: Binding<CGFloat> {
            $measuredHeight
        }

        func makeUIView(context _: Context) -> MarkdownTextView {
            createMarkdownTextView()
        }

        func updateUIView(_ uiView: MarkdownTextView, context: Context) {
            if case let .text(t) = contentSource {
                os_log("MARKDOWN updateUIView textLen=%d", log: markdownUpdateLog, type: .debug, t.count)
            }
            updateMarkdownTextView(uiView, coordinator: context.coordinator)
        }

        func makeCoordinator() -> MarkdownViewCoordinator {
            MarkdownViewCoordinator()
        }
    }

#elseif canImport(AppKit)
    import AppKit

    struct MarkdownViewRepresentable: NSViewRepresentable, MarkdownViewRepresentableBase {
        let contentSource: MarkdownView.ContentSource
        let theme: MarkdownTheme
        let width: CGFloat
        @Binding var measuredHeight: CGFloat

        var heightBinding: Binding<CGFloat> {
            $measuredHeight
        }

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
