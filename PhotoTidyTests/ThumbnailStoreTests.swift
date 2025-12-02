import XCTest
@testable import PhotoTidy

final class ThumbnailStoreTests: XCTestCase {
    func testThumbnailRequestsAreDeduplicated() async {
        let mockRepo = MockPhotoRepository()
        mockRepo.assetsMap["asset-1"] = MockPHAsset(id: "asset-1")
        let mockPipeline = MockImagePipeline()
        mockPipeline.images["asset-1"] = TestImageFactory.make(color: .red)
        let store = ThumbnailStore(photoRepository: mockRepo, imagePipeline: mockPipeline)

        async let first = store.thumbnail(for: "asset-1", target: .dashboardCard)
        async let second = store.thumbnail(for: "asset-1", target: .dashboardCard)
        let results = await (first, second)

        XCTAssertNotNil(results.0)
        XCTAssertNotNil(results.1)
        XCTAssertEqual(mockPipeline.requestCount, 1, "Image pipeline should only receive one request for deduplicated thumbnails")
    }

    func testPreloadTriggersPrefetch() async {
        let mockRepo = MockPhotoRepository()
        mockRepo.assetsMap["asset-preload"] = MockPHAsset(id: "asset-preload")
        let mockPipeline = MockImagePipeline()
        let store = ThumbnailStore(photoRepository: mockRepo, imagePipeline: mockPipeline)

        await store.preload(assetIds: ["asset-preload"], target: .dashboardCard)

        XCTAssertEqual(mockPipeline.prefetchCallCount, 1)
        XCTAssertEqual(mockPipeline.prefetchAssetCount, 1)
    }
}

private final class MockPhotoRepository: PhotoAssetFetching {
    var assetsMap: [String: PHAsset] = [:]

    func assets(for identifiers: [String]) async -> [PHAsset] {
        identifiers.compactMap { assetsMap[$0] ?? MockPHAsset(id: $0) }
    }
}

private final class MockImagePipeline: ImagePipelineType {
    var images: [String: UIImage] = [:]
    var requestCount = 0
    var prefetchCallCount = 0
    var prefetchAssetCount = 0

    func requestImage(
        for descriptor: AssetDescriptor,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping (UIImage?) -> Void
    ) {
        requestCount += 1
        completion(images[descriptor.id] ?? TestImageFactory.make(color: .blue))
    }

    func prefetch(_ assets: [PHAsset], targetSize: CGSize) {
        prefetchCallCount += 1
        prefetchAssetCount += assets.count
    }
}

private final class MockPHAsset: PHAsset {
    private let mockedId: String

    init(id: String) {
        self.mockedId = id
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var localIdentifier: String {
        mockedId
    }
}

private enum TestImageFactory {
    static func make(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
        }
    }
}
