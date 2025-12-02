
import Foundation
import Photos

enum PhotoSessionScope: Equatable {
    case all
    case month(year: Int, month: Int)
    case filter(CleanupFilterMode)
    case album(identifier: String)
}

struct PhotoSessionState: Equatable {
    var items: [PhotoItem] = []
    var isExhausted: Bool = false
    var nextOffset: Int = 0
}

protocol PhotoSessionDelegate: AnyObject {
    func photoSession(_ session: PhotoSession, didUpdate state: PhotoSessionState)
}

final class PhotoSession {
    let id: UUID
    let scope: PhotoSessionScope
    let batchSize: Int
    weak var delegate: PhotoSessionDelegate?

    private(set) var state: PhotoSessionState {
        didSet { delegate?.photoSession(self, didUpdate: state) }
    }

    init(id: UUID = UUID(), scope: PhotoSessionScope, batchSize: Int = 100) {
        self.id = id
        self.scope = scope
        self.batchSize = batchSize
        self.state = PhotoSessionState()
    }

    func append(items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        state.items.append(contentsOf: items)
        state.nextOffset = state.items.count
    }

    func markExhausted() {
        state.isExhausted = true
    }
}
