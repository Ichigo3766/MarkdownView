//
//  MarkdownTextView+LTXDelegate.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import Litext
import UIKit

extension MarkdownTextView: LTXLabelDelegate {
    public func ltxLabelSelectionDidChange(_: Litext.LTXLabel, selection _: NSRange?) {}

    public func ltxLabelDetectedUserEventMovingAtLocation(_: Litext.LTXLabel, location _: CGPoint) {}

    public func ltxLabelDidTapOnHighlightContent(_: LTXLabel, region: LTXHighlightRegion?, location: CGPoint) {
        guard let highlightRegion = region else {
            return
        }

        if let latexContent = highlightRegion.attributes[.mathLatexContent] as? String {
            presentMathPreview(for: latexContent, theme: theme)
            return
        }

        let link = highlightRegion.attributes[NSAttributedString.Key.link]
        let range = highlightRegion.stringRange
        if let url = link as? URL {
            linkHandler?(.url(url), range, location)
        } else if let string = link as? String {
            linkHandler?(.string(string), range, location)
        }
    }
}
