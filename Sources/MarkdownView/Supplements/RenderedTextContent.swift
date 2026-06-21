//
//  RenderedTextContent.swift
//  MarkdownView
//
//  Created by 秋星桥 on 6/3/25.
//

import Litext

    import UIKit

public struct RenderedTextContent {
    public let image: PlatformImage?
    public let text: String

    public typealias Map = [String: RenderedTextContent]

    public init(image: PlatformImage?, text: String) {
        self.image = image
        self.text = text
    }
}
