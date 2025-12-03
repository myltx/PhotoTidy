import Foundation
import Photos

actor PhotoLibraryPreheater {
    private let photoRepository: PhotoRepository
    private let thumbnailStore: ThumbnailStore
    private let progressStore: PhotoLibraryPreheatProgressStore
    private let batchSize: Int
    private let pauseNanoseconds: UInt64
    private var currentTask: Task<Void, Never>?

    init(
        photoRepository: PhotoRepository = PhotoRepository(),
        thumbnailStore: ThumbnailStore,
        progressStore: PhotoLibraryPreheatProgressStore = PhotoLibraryPreheatProgressStore(),
        batchSize: Int = 30,
        pauseNanoseconds: UInt64 = 200_000_000
    ) {
        self.photoRepository = photoRepository
        self.thumbnailStore = thumbnailStore
        self.progressStore = progressStore
        self.batchSize = batchSize
        self.pauseNanoseconds = pauseNanoseconds
    }

    func start() {
        guard currentTask == nil else { return }
        currentTask = Task(priority: .utility) { [weak self] in
            await self?.preheatLoop()
        }
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    func resetProgress() {
        progressStore.reset()
    }

    private func preheatLoop() async {
        while !(Task.isCancelled) {
            if shouldPauseForThermalState() {
                try? await Task.sleep(nanoseconds: pauseNanoseconds * 4)
                continue
            }
            let totalCount = await photoRepository.assetCount()
            guard totalCount > 0 else {
                try? await Task.sleep(nanoseconds: pauseNanoseconds * 2)
                continue
            }
            var checkpoint = progressStore.checkpoint()
            if checkpoint.assetCount != totalCount || checkpoint.nextOffset >= totalCount {
                checkpoint = .zero
            }
            let upperBound = min(checkpoint.nextOffset + batchSize, totalCount)
            let range = checkpoint.nextOffset..<upperBound
            let descriptors = await photoRepository.descriptors(range: range)
            if descriptors.isEmpty {
                progressStore.reset()
                break
            }
            let ids = descriptors.map(\.id)
            await preheatThumbnails(for: ids)
            progressStore.save(nextOffset: upperBound, assetCount: totalCount)
            if upperBound >= totalCount {
                progressStore.reset()
                break
            }
            try? await Task.sleep(nanoseconds: pauseNanoseconds)
        }
        currentTask = nil
    }

    private func preheatThumbnails(for ids: [String]) async {
        guard !ids.isEmpty else { return }
        for id in ids {
            if Task.isCancelled { break }
            _ = await thumbnailStore.thumbnail(for: id, target: .tinderCard)
            await Task.yield()
        }
    }

    private func shouldPauseForThermalState() -> Bool {
        let thermalState = ProcessInfo.processInfo.thermalState
        return thermalState == .serious || thermalState == .critical
    }
}
