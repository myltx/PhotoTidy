import Foundation

actor AnalysisWorker {
    private let scheduler: AnalysisScheduler
    private let database: PhotoStoreDatabase
    private let onUpdates: () -> Void
    private var isRunning = false

    init(
        scheduler: AnalysisScheduler,
        database: PhotoStoreDatabase,
        onUpdates: @escaping () -> Void
    ) {
        self.scheduler = scheduler
        self.database = database
        self.onUpdates = onUpdates
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task.detached(priority: .utility) { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while isRunning {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let batch = await scheduler.drain(maxCount: 50)
            guard !batch.isEmpty else { continue }
            database.applyAnalysis(tasks: batch)
            onUpdates()
        }
    }
}
