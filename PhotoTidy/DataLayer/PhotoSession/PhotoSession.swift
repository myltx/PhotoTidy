
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
    var trimmedCount: Int = 0
}

protocol PhotoSessionDelegate: AnyObject {
    func photoSession(_ session: PhotoSession, didUpdate state: PhotoSessionState)
}

final class PhotoSession {
    let id: UUID
    let scope: PhotoSessionScope
    let batchSize: Int
    private let windowLimit: Int?
    weak var delegate: PhotoSessionDelegate?

    private(set) var state: PhotoSessionState {
        didSet { delegate?.photoSession(self, didUpdate: state) }
    }

    init(id: UUID = UUID(), scope: PhotoSessionScope, batchSize: Int = 100, windowLimit: Int? = nil) {
        self.id = id
        self.scope = scope
        self.batchSize = batchSize
        self.windowLimit = windowLimit
        self.state = PhotoSessionState()
    }

    func append(items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        state.items.append(contentsOf: items)
        state.nextOffset += items.count
        trimIfNeeded()
    }

    func markExhausted() {
        state.isExhausted = true
    }

    private func trimIfNeeded() {
        guard let limit = windowLimit, state.items.count > limit else { return }
        let overflow = state.items.count - limit
        state.items.removeFirst(overflow)
        state.trimmedCount += overflow
    }
}
