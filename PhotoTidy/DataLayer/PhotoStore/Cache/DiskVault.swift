import Foundation
import CryptoKit

actor DiskVault {
    private let database: PhotoStoreDatabase
    private let thumbnailManifestURL: URL
    private let thumbnailsDirectory: URL
    private var thumbnailStore: [String: PhotoThumbnailDescriptor] = [:]

    init(database: PhotoStoreDatabase, baseDirectory: URL? = nil) {
        self.database = database
        let baseURL: URL
        if let baseDirectory {
            baseURL = baseDirectory
        } else {
            baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("PhotoStoreVault", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        thumbnailManifestURL = baseURL.appendingPathComponent("thumbnails.json")
        thumbnailsDirectory = baseURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        thumbnailStore = Self.loadDictionary(url: thumbnailManifestURL) ?? [:]
    }

    func bootstrapIfNeeded(with assets: [PhotoAssetMetadata]) {
        for asset in assets {
            thumbnailStore[asset.id] = PhotoThumbnailDescriptor(
                assetId: asset.id,
                palette: asset.palette,
                source: .disk
            )
        }
        persistThumbnails()
    }

    func metadata(for ids: [String]) -> [PhotoAssetMetadata] {
        database.metadata(for: ids)
    }

    func store(metadata: [PhotoAssetMetadata]) {
        // 元数据由 SQLite 维护，此处无需重复写入
    }

    func store(thumbnails: [PhotoThumbnailDescriptor]) {
        for descriptor in thumbnails {
            thumbnailStore[descriptor.assetId] = descriptor
        }
        persistThumbnails()
    }

    func thumbnails(for ids: [String]) -> [PhotoThumbnailDescriptor] {
        ids.compactMap { thumbnailStore[$0] }
    }

    func store(thumbnailData: Data, for assetId: String) {
        let url = thumbnailFileURL(for: assetId)
        try? thumbnailData.write(to: url, options: .atomic)
    }

    func thumbnailData(for assetId: String) -> Data? {
        let url = thumbnailFileURL(for: assetId)
        return try? Data(contentsOf: url)
    }

    func clear() {
        thumbnailStore.removeAll()
        try? FileManager.default.removeItem(at: thumbnailManifestURL)
        try? FileManager.default.removeItem(at: thumbnailsDirectory)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        persistThumbnails()
    }

    private func persistThumbnails() {
        Self.persistDictionary(thumbnailStore, to: thumbnailManifestURL)
    }

    private static func loadDictionary<T: Decodable>(url: URL) -> [String: T]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([String: T].self, from: data)
        } catch {
            return nil
        }
    }

    private static func persistDictionary<T: Encodable>(_ dictionary: [String: T], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(dictionary) else { return }
        try? data.write(to: url)
    }

    private func thumbnailFileURL(for assetId: String) -> URL {
        let hash = SHA256.hash(data: Data(assetId.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return thumbnailsDirectory.appendingPathComponent("\(filename).jpg")
    }
}
