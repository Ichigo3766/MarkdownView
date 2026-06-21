//
//  Created by ktiays on 2025/1/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Combine
import CoreText
import Litext
import MarkdownParser
import UIKit

public final class MarkdownTextView: UIView {
    public var linkHandler: ((LinkPayload, NSRange, CGPoint) -> Void)?
    public var codePreviewHandler: ((String?, NSAttributedString) -> Void)?

    public internal(set) var document: PreprocessedContent = .init()
    public let textView: LTXLabel = .init()
    public var theme: MarkdownTheme = .default {
        didSet {
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            // Theme change invalidates all cached block renders since fonts/colors differ.
            cachedBlockSegments.removeAll()
            setMarkdown(document)
        }
    }

    // Block-level render cache: stores rendered output per MarkdownBlockNode so
    // unchanged blocks can be reused on the next streaming update without re-rendering.
    struct CachedBlockSegment {
        let node: MarkdownBlockNode
        let attributedString: NSAttributedString
        let subviews: [UIView]
    }
    var cachedBlockSegments: [CachedBlockSegment] = []

    // Persistent mutable attributed string for the entire document.
    // We mutate only the dirty tail in-place instead of rebuilding from scratch
    // on every streaming update — converts O(n_total) concat to O(n_dirty).
    var cachedAttributedString: NSMutableAttributedString = .init()

    var contextViews: [UIView] = []
    /// Cached value for setCodeBlockAutoScroll — guards against O(n_views) iteration
    /// on every no-change updateUIView call during streaming (60fps × N messages).
    private var _autoScrollEnabled: Bool = false
    /// Cached value for setCodeBlockBarHidden — same guard pattern.
    private var _barHidden: Bool = false
    var cancellables = Set<AnyCancellable>()
    let contentSubject = CurrentValueSubject<PreprocessedContent, Never>(.init())

    let viewProvider: ReusableViewProvider

    public init(viewProvider: ReusableViewProvider = .init()) {
        self.viewProvider = viewProvider
        super.init(frame: .zero)
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.selectionBackgroundColor = theme.colors.selectionBackground
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setupCombine()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        textView.preferredMaxLayoutWidth = bounds.width
    }

    override public var intrinsicContentSize: CGSize {
        textView.intrinsicContentSize
    }

    public func boundingSize(for width: CGFloat) -> CGSize {
        textView.preferredMaxLayoutWidth = width
        return textView.intrinsicContentSize
    }

    func setMarkdownManually(_ content: PreprocessedContent) {
        assert(Thread.isMainThread)
        resetCombine()
        use(content)
    }

    public func setMarkdown(_ content: PreprocessedContent) {
        contentSubject.send(content)
    }

    func reset() {
        assert(Thread.isMainThread)
        use(.init())
        setupCombine()
    }

    /// Enables or disables auto-scroll-to-bottom on all CodeView subviews.
    /// Call with `true` during streaming, `false` when streaming ends.
    public func setCodeBlockAutoScroll(_ enabled: Bool) {
        guard enabled != _autoScrollEnabled else { return }
        _autoScrollEnabled = enabled
        for view in contextViews {
            if let codeView = view as? CodeView {
                codeView.isStreaming = enabled
            }
        }
    }

    /// Shows or hides the built-in header bar on all CodeView subviews.
    /// Call with `true` when a container view supplies its own header.
    public func setCodeBlockBarHidden(_ hidden: Bool) {
        guard hidden != _barHidden else { return }
        _barHidden = hidden
        for view in contextViews {
            if let codeView = view as? CodeView {
                codeView.barHidden = hidden
            }
        }
    }
}
