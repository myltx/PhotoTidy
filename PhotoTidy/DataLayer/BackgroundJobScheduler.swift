import Foundation

/// 统一调度后台预处理任务（相似度、模糊检测、元数据刷新等）
actor BackgroundJobScheduler {
    enum Job: Hashable {
        case similarity
        case blur
        case metadataRefresh
        case cacheWarmup
        case custom(String)
    }

    private var jobs: [Job: Task<Void, Never>] = [:]

    func schedule(job: Job, priority: TaskPriority = .utility, action: @escaping @Sendable () async -> Void) {
        cancel(job: job)
        let task = Task(priority: priority) {
            await action()
        }
        jobs[job] = task
    }

    func cancel(job: Job) {
        if let existing = jobs[job] {
            existing.cancel()
            jobs.removeValue(forKey: job)
        }
    }

    func cancelAll() {
        for job in jobs.keys {
            cancel(job: job)
        }
    }
}
