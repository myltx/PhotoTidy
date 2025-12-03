import Foundation

struct PhotoLibraryPreheatCheckpoint: Codable {
    var nextOffset: Int
    var assetCount: Int

    static let zero = PhotoLibraryPreheatCheckpoint(nextOffset: 0, assetCount: 0)
}

final class PhotoLibraryPreheatProgressStore {
    private let defaults: UserDefaults
    private let storageKey = "photoLibraryPreheatCheckpoint"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func checkpoint() -> PhotoLibraryPreheatCheckpoint {
        guard
            let data = defaults.data(forKey: storageKey),
            let checkpoint = try? JSONDecoder().decode(PhotoLibraryPreheatCheckpoint.self, from: data)
        else {
            return .zero
        }
        return checkpoint
    }

    func save(nextOffset: Int, assetCount: Int) {
        let payload = PhotoLibraryPreheatCheckpoint(nextOffset: max(0, nextOffset), assetCount: max(0, assetCount))
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }
}
