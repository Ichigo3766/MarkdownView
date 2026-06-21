# MarkdownView

A high-performance pure UIKit framework for rendering Markdown with real-time streaming support. Built for [Open Relay](https://github.com/Ichigo3766/Open-UI), an iOS client for Open WebUI.

## Platform

- **iOS 16.0+** / **iPadOS 16.0+**

## Architecture

### Streaming Pipeline (O(delta) per token)
- **Block-level render cache** (`CachedBlockSegment`): Each `MarkdownBlockNode` is rendered once and cached. Only changed blocks are re-rendered.
- **Persistent `NSMutableAttributedString` mutation**: Dirty tail is deleted and replaced in-place — CoreText only re-lays out the changed portion.
- **Deferred layout**: `setNeedsLayout()` lets the run loop coalesce passes — no per-token stalls.
- **Incremental streaming parser**: Maintains a "stable prefix" (parsed once, cached). Only the short "live tail" is re-parsed each tick.
- **Virtual line windowing** (CodeView): Large code blocks render only the visible viewport + overscan — O(viewport), not O(total lines).
- **`StreamingCodeBlockView`**: Bypasses the markdown parser entirely for unclosed fences — O(delta) append + O(viewport) windowed render.

### Code Highlighting
- **HighlightSwift** (pure Swift/JavaScriptCore) with async per-block highlighting
- 300ms debounce during streaming — no flickering
- LRU cache (512 entries) with dark/light appearance variants
- **`CodeHighlighter.warmUp()`** — call at app launch to front-load JSContext init

### Math Rendering
- **SwiftMath** for LaTeX → image rendering
- Async two-pass: text renders immediately, math images arrive off-main-thread
- LRU cache (256 entries)
- Tap-to-preview via QuickLook

### Heading Levels
- h1–h6 render at distinct sizes (1.6×–0.85× body) via `fontForHeadingLevel(_:)`
- Configurable through `MarkdownTheme`

## Features

- 🚀 **120Hz streaming** — smooth token-by-token rendering on ProMotion displays
- 🎨 **Syntax highlighting** — async, debounced, cached, dark/light aware
- 📐 **Configurable spacing** — paragraph, line, heading, blockquote, list
- 📊 **Math rendering** — LaTeX with tap-to-preview
- 🔗 **Clickable links** — opens via notification (no setup needed)
- ✅ **Task lists, tables, blockquotes** — full GFM support
- 📱 **iPad multitasking** — correct sizing in Split View / Stage Manager

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Ichigo3766/MarkdownView", branch: "main"),
]
```

## Usage

### SwiftUI

```swift
import MarkdownView

struct ContentView: View {
    var body: some View {
        MarkdownView("# Hello World\n\nLinks are [clickable](https://example.com)!")
    }
}
```

### Streaming Code Block (bypass parser for live code)

```swift
StreamingCodeBlockView(
    language: "python",
    content: liveCode,
    isStreaming: true,
    theme: .default
)
```

### Modifiers

```swift
MarkdownView(text, theme: customTheme)
    .codeAutoScroll(true)    // auto-scroll code blocks during streaming
    .codeBarHidden(true)     // hide built-in code block header
```

### Theme Customization

```swift
var theme = MarkdownTheme.default
theme.align(to: 18)  // scale all fonts to 18pt base
theme.colors.body = .white
theme.spacings.paragraphSpacing = 12
```

## License

MIT License. See [LICENSE](LICENSE).

### Acknowledgments

- Original framework by [Lakr233](https://github.com/Lakr233/MarkdownView)
- Code adapted from [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) by Guillermo Gonzalez (MIT License)
