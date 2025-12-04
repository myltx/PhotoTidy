import Foundation

struct MockAssetProvider {
    private let calendar = Calendar(identifier: .gregorian)

    func makeAssets(count: Int) -> [PhotoAssetMetadata] {
        var assets: [PhotoAssetMetadata] = []
        assets.reserveCapacity(count)
        var groupPool: [String] = []
        let albums = ["所有照片", "最近项目", "旅行日记", "家庭相册", "工作素材"]
        for index in 0..<count {
            let randomDay = Int.random(in: 0..<1500)
            let captureDate = calendar.date(byAdding: .day, value: -randomDay, to: Date()) ?? Date()
            let byteSize = Int.random(in: 200_000..<80_000_000)
            let width = Int.random(in: 800..<6000)
            let height = Int.random(in: 800..<4000)
            let palette = ThumbnailPalette(startHex: hexColor(seed: index * 19), endHex: hexColor(seed: index * 29))
            var tags: PhotoClassification = []
            var blurScore = Double.random(in: 0...1)
            var documentScore = Double.random(in: 0...1)
            var similarityScore = Double.random(in: 0...1)

            if byteSize > 20_000_000 { tags.insert(.largeFile) }
            if Int.random(in: 0..<5) == 0 { tags.insert(.screenshot) }
            if Int.random(in: 0..<6) == 0 { tags.insert(.document); documentScore = Double.random(in: 0.7...0.95) }
            if Int.random(in: 0..<7) == 0 { tags.insert(.textHeavy) }
            if Int.random(in: 0..<8) == 0 { tags.insert(.blurred); blurScore = Double.random(in: 0.75...0.99) }

            let decisionRoll = Int.random(in: 0..<20)
            let decision: PhotoDecisionState
            if decisionRoll == 0 {
                decision = .pendingDeletion
            } else if decisionRoll == 1 {
                decision = .skipped
            } else {
                decision = .clean
            }

            var groupIdentifier: String?
            if index % 9 == 0 {
                let groupId = "grp-\(index / 9)"
                groupPool.append(groupId)
                groupIdentifier = groupId
                similarityScore = Double.random(in: 0.8...0.99)
                tags.insert(.blurred)
            } else if Bool.random(), let existing = groupPool.randomElement() {
                groupIdentifier = existing
                similarityScore = Double.random(in: 0.6...0.9)
            }

            let mediaType = randomMediaType(index: index)
            let fileName = mockFileName(index: index, mediaType: mediaType)
            let albumName = albums.randomElement() ?? "所有照片"

            let metadata = PhotoAssetMetadata(
                id: "mock-\(index)",
                captureDate: captureDate,
                fileName: fileName,
                byteSize: byteSize,
                pixelWidth: width,
                pixelHeight: height,
                mediaType: mediaType,
                albumName: albumName,
                tags: tags,
                groupIdentifier: groupIdentifier,
                decision: decision,
                palette: palette,
                score: Double.random(in: 0.4...0.99),
                blurScore: blurScore,
                documentScore: documentScore,
                similarityScore: similarityScore
            )
            assets.append(metadata)
        }
        return assets.sorted { $0.captureDate > $1.captureDate }
    }

    private func hexColor(seed: Int) -> String {
        var generator = SeededGenerator(seed: UInt64(abs(seed) + 1))
        let r = Int.random(in: 0...255, using: &generator)
        let g = Int.random(in: 0...255, using: &generator)
        let b = Int.random(in: 0...255, using: &generator)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func randomMediaType(index: Int) -> PhotoAssetMetadata.MediaType {
        let roll = Int.random(in: 0..<10)
        switch roll {
        case 0:
            return .video
        case 1:
            return .live
        case 2:
            return .gif
        default:
            return .photo
        }
    }

    private func mockFileName(index: Int, mediaType: PhotoAssetMetadata.MediaType) -> String {
        switch mediaType {
        case .video:
            return String(format: "MOV_%04d.MOV", index)
        case .gif:
            return String(format: "IMG_%04d.GIF", index)
        default:
            return String(format: "IMG_%04d.JPG", index)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}
