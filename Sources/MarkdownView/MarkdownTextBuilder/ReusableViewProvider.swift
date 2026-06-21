//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import DequeModule
import UIKit

private class ObjectPool<T: Equatable & Hashable> {
    private let factory: () -> T
    fileprivate lazy var objects: Deque<T> = .init()

    /// Maximum number of idle objects retained in the pool.
    /// When exceeded, the oldest objects are evicted to free memory.
    private let maxPoolSize: Int

    init(maxPoolSize: Int = 32, _ factory: @escaping () -> T) {
        self.maxPoolSize = maxPoolSize
        self.factory = factory
    }

    func acquire() -> T {
        if let object = objects.popFirst() {
            object
        } else {
            factory()
        }
    }

    func stash(_ object: T) {
        objects.append(object)
        // Evict excess objects to prevent unbounded growth in long chats.
        while objects.count > maxPoolSize {
            objects.removeFirst()
        }
    }

    func reorder(matching sequence: [T]) {
        var current = Set(objects)
        objects.removeAll()
        for content in sequence where current.contains(content) {
            objects.append(content)
            current.remove(content)
        }
        for reset in current {
            objects.append(reset)
        }
    }
}

public final class ReusableViewProvider {
    private let codeViewPool: ObjectPool<CodeView> = .init {
        CodeView(frame: .zero)
    }

    private let tableViewPool: ObjectPool<TableView> = .init {
        TableView(frame: .zero)
    }

    private let lock = NSLock()

    public init() {}

    func lockPool() {
        lock.lock()
    }

    func unlockPool() {
        lock.unlock()
    }

    func removeAll() {
        codeViewPool.objects.removeAll()
        tableViewPool.objects.removeAll()
    }

    func acquireCodeView() -> CodeView {
        codeViewPool.acquire()
    }

    func stashCodeView(_ codeView: CodeView) {
        codeViewPool.stash(codeView)
    }

    func acquireTableView() -> TableView {
        tableViewPool.acquire()
    }

    func stashTableView(_ tableView: TableView) {
        tableViewPool.stash(tableView)
    }

    func reorderViews(matching sequence: [PlatformView]) {
        let orderedCodeView = sequence.compactMap { $0 as? CodeView }
        let orderedTableView = sequence.compactMap { $0 as? TableView }

        codeViewPool.reorder(matching: orderedCodeView)
        tableViewPool.reorder(matching: orderedTableView)
    }
}
