import Foundation

/// 简单的多优先级分析队列：支持高优先级抢占与去重。
actor AnalysisScheduler {
    enum Priority {
        case high
        case normal
    }

    private var highQueue: [String] = []
    private var normalQueue: [String] = []
    private var queuedPriority: [String: Priority] = [:]

    func enqueue(_ ids: [String], priority: Priority) {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let existing = queuedPriority[id] {
                // 允许从 normal 提升到 high
                if existing == .normal, priority == .high {
                    normalQueue.removeAll { $0 == id }
                    highQueue.append(id)
                    queuedPriority[id] = .high
                }
                continue
            }
            queuedPriority[id] = priority
            switch priority {
            case .high:
                highQueue.append(id)
            case .normal:
                normalQueue.append(id)
            }
        }
    }

    func nextBatch(limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(limit)

        while result.count < limit, !highQueue.isEmpty {
            result.append(highQueue.removeFirst())
        }
        while result.count < limit, !normalQueue.isEmpty {
            result.append(normalQueue.removeFirst())
        }

        for id in result {
            queuedPriority.removeValue(forKey: id)
        }
        return result
    }

    func hasPending() -> Bool {
        !highQueue.isEmpty || !normalQueue.isEmpty
    }

    func reset() {
        highQueue.removeAll()
        normalQueue.removeAll()
        queuedPriority.removeAll()
    }
}

