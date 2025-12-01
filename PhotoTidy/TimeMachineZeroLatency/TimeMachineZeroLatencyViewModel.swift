import Foundation
import Combine
import Photos

@MainActor
final class TimeMachineZeroLatencyViewModel: ObservableObject {
    @Published private(set) var sections: [TimeMachineMonthSection] = []
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isLoading: Bool = false

    private let metadataRepository: MetadataRepository
    private let metaStore = TimeMachineMetaStore()
    private let progressStore = TimeMachineProgressStore()
    private let skippedStore = SkippedPhotoStore()
    private let assetIndexStore = AssetIndexStore()
    private let imageManager = TimeMachineImageManagerWrapper()
    private let photoRepository = PhotoRepository()
    private let analysisManager = TimeMachineAnalysisManager()
    private let analysisCache = PhotoAnalysisCacheStore()
    private var cancellables: Set<AnyCancellable> = []
    private var latestSnapshot: MetadataSnapshot = .empty

    init() {
        self.metadataRepository = MetadataRepository(analysisCache: analysisCache)
        metadataRepository.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                Task { await self.handle(snapshot: snapshot) }
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        if authorizationStatus.isAuthorized {
            metadataRepository.bootstrapIfNeeded()
        }
    }

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if status.isAuthorized {
                    self?.metadataRepository.bootstrapIfNeeded()
                }
            }
        }
    }

    private func handle(snapshot: MetadataSnapshot) async {
        guard authorizationStatus.isAuthorized else { return }
        isLoading = true
        await metaStore.rebuild(
            snapshot: snapshot,
            progressStore: progressStore,
            skippedStore: skippedStore
        )
        let sections = await metaStore.sections()
        self.sections = sections
        isLoading = false
    }

    private func makeDetailViewModel(for month: MonthInfo, autoLoad: Bool) -> TimeMachineMonthDetailViewModel {
        TimeMachineMonthDetailViewModel(
            month: month,
            snapshot: latestSnapshot,
            assetIndexStore: assetIndexStore,
            photoRepository: photoRepository,
            imageManager: imageManager,
            analysisManager: analysisManager,
            autoLoad: autoLoad
        )
    }

    func detailViewModel(for month: MonthInfo) -> TimeMachineMonthDetailViewModel {
        makeDetailViewModel(for: month, autoLoad: true)
    }

    func prepareSession(for month: MonthInfo) async -> Bool {
        let detailVM = makeDetailViewModel(for: month, autoLoad: false)
        return await detailVM.injectSessionIntoCleanup()
    }
}
