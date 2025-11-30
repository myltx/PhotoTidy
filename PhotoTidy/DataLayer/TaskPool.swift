import Foundation

/// 统一管理 Task 的声明周期，避免页面离开后任务仍在占用资源
actor TaskPool {
    enum Scope: Hashable {
        case metadata
        case paging
        case analysis
        case prefetch
        case module(String)
    }

    private var tasks: [Scope: [UUID: Task<Void, Never>]] = [:]

    @discardableResult
    func insert(_ task: Task<Void, Never>, scope: Scope) -> UUID {
        let id = UUID()
        var scoped = tasks[scope] ?? [:]
        scoped[id] = task
        tasks[scope] = scoped
        Task.detached { [self, scope, id] in
            _ = await task.value
            await self.remove(scope: scope, id: id)
        }
        return id
    }

    func cancel(scope: Scope) {
        guard let scoped = tasks[scope] else { return }
        for (_, task) in scoped {
            task.cancel()
        }
        tasks.removeValue(forKey: scope)
    }

    func cancelAll() {
        for scope in tasks.keys {
            cancel(scope: scope)
        }
    }

    private func remove(scope: Scope, id: UUID) {
        guard var scoped = tasks[scope] else { return }
        scoped.removeValue(forKey: id)
        if scoped.isEmpty {
            tasks.removeValue(forKey: scope)
        } else {
            tasks[scope] = scoped
        }
    }
}
