//
//  MarkdownBlockRenderCache.swift
//  MarkdownView
//
//  Parse-once / render-once cache for large, finished (non-streaming) messages.
//
//  A giant message is expensive to render because Litext lays out and measures
//  the whole attributed string synchronously on the main thread. To keep the UI
//  responsive we:
//    1. Parse the markdown ONCE, off the main thread.
//    2. Render its math images ONCE, off the main thread.
//    3. Split the result into small per-chunk PreprocessedContent objects.
//    4. Cache that chunk array keyed by (content hash ⊕ theme signature).
//
//  Because a finished message's text is immutable, the content hash IS a stable
//  identity — no message ID needs to be threaded through the view hierarchy.
//
//  The cache is @MainActor so all access is serialized with no data races. The
//  heavy work runs inside a detached task; only the final store hops back to the
//  main actor.
//

import Foundation
import MarkdownParser

@MainActor
public final class MarkdownBlockRenderCache {
    public static let shared = MarkdownBlockRenderCache()

    /// Bounded LRU of recently rendered messages. 40 messages is plenty for a
    /// scroll window while keeping memory in check (large messages carry math
    /// images and attributed strings).
    private let countLimit = 40

    private struct Entry {
        let chunks: [MarkdownTextView.PreprocessedContent]
    }

    private var storage: [Int: Entry] = [:]
    /// Most-recently-used ordering; last element is newest.
    private var lru: [Int] = []
    /// Keys with an in-flight build so we don't launch duplicate parses.
    private var inFlight: Set<Int> = []

    private init() {}

    // MARK: - Keying

    /// Stable cache key from the raw text and a cheap theme signature.
    public static func key(content: String, theme: MarkdownTheme) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(Int(theme.fonts.body.pointSize.rounded()))
        hasher.combine(Int(theme.fonts.code.pointSize.rounded()))
        hasher.combine(theme.colors.body)
        hasher.combine(theme.colors.code)
        return hasher.finalize()
    }

    // MARK: - Synchronous lookup

    /// Returns cached chunks if present, marking the entry most-recently-used.
    public func lookup(content: String, theme: MarkdownTheme) -> [MarkdownTextView.PreprocessedContent]? {
        let k = Self.key(content: content, theme: theme)
        guard let entry = storage[k] else { return nil }
        touch(k)
        return entry.chunks
    }

    // MARK: - Async build

    /// Parses + renders math + splits `content` off the main thread and stores the
    /// result. `completion` is invoked on the main actor when the chunks are ready
    /// (or immediately if the entry already exists / a build is already running for
    /// this key and finishes). Safe to call repeatedly; duplicate builds are
    /// coalesced via `inFlight`.
    public func build(
        content: String,
        theme: MarkdownTheme,
        chunkCharBudget: Int = MarkdownTextView.PreprocessedContent.defaultChunkCharBudget,
        completion: @escaping @MainActor ([MarkdownTextView.PreprocessedContent]) -> Void
    ) {
        let k = Self.key(content: content, theme: theme)

        if let entry = storage[k] {
            touch(k)
            completion(entry.chunks)
            return
        }
        guard !inFlight.contains(k) else {
            // A build is already running; the caller will pick it up on the next
            // layout pass via lookup(). We don't queue multiple completions.
            return
        }
        inFlight.insert(k)

        let capturedContent = content
        let capturedTheme = theme

        Task.detached(priority: .userInitiated) {
            // 1. Parse (off-main).
            let parser = MarkdownParser()
            let result = parser.parse(capturedContent)

            // 2. Build a parent PreprocessedContent WITHOUT math yet.
            let parent = MarkdownTextView.PreprocessedContent(parserResultNoMath: result)

            // 3. Render math into `parent.rendered` (off-main), then split.
            //    renderMathAsync hops to the main actor for its completion, so we
            //    finish the split + store there. If there's no pending math it
            //    still calls completion on the main actor.
            await MainActor.run {
                parent.renderMathAsync(theme: capturedTheme) { [weak self] in
                    guard let self else { return }
                    let chunks = parent.split(chunkCharBudget: chunkCharBudget)
                    self.store(key: k, chunks: chunks)
                    self.inFlight.remove(k)
                    completion(chunks)
                }
            }
        }
    }

    // MARK: - Store / LRU

    private func store(key: Int, chunks: [MarkdownTextView.PreprocessedContent]) {
        storage[key] = Entry(chunks: chunks)
        touch(key)
        evictIfNeeded()
    }

    private func touch(_ key: Int) {
        if let idx = lru.firstIndex(of: key) {
            lru.remove(at: idx)
        }
        lru.append(key)
    }

    private func evictIfNeeded() {
        while lru.count > countLimit {
            let oldest = lru.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    /// Clears the entire cache (e.g. on memory pressure or theme-wide changes).
    public func removeAll() {
        storage.removeAll()
        lru.removeAll()
        inFlight.removeAll()
    }
}
