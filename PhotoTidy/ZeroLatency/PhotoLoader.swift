import Foundation
import Photos
import Combine

@MainActor
protocol PhotoLoaderDelegate: AnyObject {
    func photoLoader(_ loader: PhotoLoader, didUpdateFetchResult fetchResult: PHFetchResult<PHAsset>)
    func photoLoader(_ loader: PhotoLoader, didLoadAssets assets: [PHAsset])
}

@MainActor
final class PhotoLoader: ObservableObject {
    
    enum LoadTrigger {
        case initial
        case userScrolling
        case background
    }

    @Published private(set) var items: [AssetItem] = []
    @Published private(set) var isBootstrapping = false

    weak var delegate: PhotoLoaderDelegate?

    private let imageCache: ImageCache
    private var fetchResult: PHFetchResult<PHAsset>?
    private var currentUpperBound = 0
    private var isLoadingPage = false
    private var backgroundPrefetchTask: Task<Void, Never>?
    private var cachingRange: Range<Int> = 0..<0

    private let firstPageSize = 100
    private let pageSize = 200
    private let bufferThreshold = 80
    private let preheatDistance = 45

    init(imageCache: ImageCache) {
        self.imageCache = imageCache
    }

    func start() {
        guard fetchResult == nil else { return }
        isBootstrapping = true
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result
        delegate?.photoLoader(self, didUpdateFetchResult: result)

        let initialRange = 0..<min(firstPageSize, result.count)
        load(range: initialRange, trigger: .initial)
        scheduleBackgroundPrefetchIfNeeded()
    }

    func stop() {
        backgroundPrefetchTask?.cancel()
        backgroundPrefetchTask = nil
        imageCache.stopCachingAll()
    }

    func reloadLibrary() {
        stop()
        items = []
        fetchResult = nil
        currentUpperBound = 0
        isLoadingPage = false
        cachingRange = 0..<0
        start()
    }

    func ensurePagingBuffer(forDisplayedIndex index: Int) {
        guard let fetchResult else { return }
        updatePrefetchWindow(centeredAt: index, fetchResult: fetchResult)
        let shouldLoadNext = currentUpperBound - index <= bufferThreshold
        if shouldLoadNext {
            loadNextPage(trigger: .userScrolling)
        }
    }

    func visibleRangeDidChange(_ range: Range<Int>) {
        guard let fetchResult else { return }
        let expanded = max(0, range.lowerBound - preheatDistance)..<min(fetchResult.count, range.upperBound + preheatDistance)
        cachingRange = expanded
        imageCache.updateCaching(fetchResult: fetchResult, newRange: expanded)
    }

    func currentFetchResult() -> PHFetchResult<PHAsset>? {
        fetchResult
    }

    private func loadNextPage(trigger: LoadTrigger) {
        guard let fetchResult else { return }
        guard !isLoadingPage else { return }
        guard currentUpperBound < fetchResult.count else { return }
        let range = currentUpperBound..<min(currentUpperBound + pageSize, fetchResult.count)
        load(range: range, trigger: trigger)
    }

    private func load(range: Range<Int>, trigger: LoadTrigger) {
        guard let fetchResult else { return }
        guard !range.isEmpty else {
            if trigger == .initial {
                isBootstrapping = false
            }
            return
        }
        isLoadingPage = true
        Task.detached(priority: trigger == .background ? .utility : .userInitiated) { [weak self, fetchResult] in
            let items = PhotoLoader.makeItems(fetchResult: fetchResult, range: range)
            await self?.handleLoadedItems(items, range: range, trigger: trigger)
        }
    }

    private func handleLoadedItems(_ newItems: [AssetItem], range: Range<Int>, trigger: LoadTrigger) {
        guard !Task.isCancelled else { return }
        items.append(contentsOf: newItems)
        currentUpperBound = max(currentUpperBound, range.upperBound)
        delegate?.photoLoader(self, didLoadAssets: newItems.map { $0.asset })
        isLoadingPage = false
        if trigger == .initial {
            isBootstrapping = false
        }
    }

    private func scheduleBackgroundPrefetchIfNeeded() {
        backgroundPrefetchTask?.cancel()
        backgroundPrefetchTask = Task(priority: .utility) { [weak self] in
            while let self = self {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 350_000_000)
                let shouldContinue = await self.performBackgroundLoad()
                if !shouldContinue { break }
            }
        }
    }

    @MainActor
    private func performBackgroundLoad() -> Bool {
        loadNextPage(trigger: .background)
        guard let fetchResult = fetchResult else { return false }
        return currentUpperBound < fetchResult.count
    }

    private func updatePrefetchWindow(centeredAt index: Int, fetchResult: PHFetchResult<PHAsset>) {
        guard fetchResult.count > 0 else { return }
        let lower = max(0, index - preheatDistance)
        let upper = min(fetchResult.count, index + preheatDistance)
        let newRange = lower..<upper
        if newRange != cachingRange {
            cachingRange = newRange
            imageCache.updateCaching(fetchResult: fetchResult, newRange: newRange)
        }
    }

    nonisolated private static func makeItems(fetchResult: PHFetchResult<PHAsset>, range: Range<Int>) -> [AssetItem] {
        guard !range.isEmpty else { return [] }
        var results: [AssetItem] = []
        for index in range {
            guard index < fetchResult.count else { break }
            let asset = fetchResult.object(at: index)
            let creation = asset.creationDate ?? asset.modificationDate ?? Date()
            results.append(AssetItem(id: asset.localIdentifier, asset: asset, creationDate: creation))
        }
        return results
    }
}
