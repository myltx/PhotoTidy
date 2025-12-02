import Foundation
import Photos
import UIKit

actor FullImageStore {
    private var pagers: [UUID: LargeImagePager] = [:]

    func configure(sessionId: UUID, assets: [PHAsset], targetSize: CGSize) async -> [String: UIImage] {
        let pager = pager(for: sessionId)
        await pager.configure(assets: assets, targetSize: targetSize)
        return await pager.ensureWindow(centerIndex: 0)
    }

    func ensureWindow(sessionId: UUID, centerIndex: Int) async -> [String: UIImage] {
        let pager = pager(for: sessionId)
        return await pager.ensureWindow(centerIndex: centerIndex)
    }

    func reset(sessionId: UUID) async {
        guard let pager = pagers[sessionId] else { return }
        await pager.configure(assets: [], targetSize: .zero)
        pagers.removeValue(forKey: sessionId)
    }

    private func pager(for sessionId: UUID) -> LargeImagePager {
        if let existing = pagers[sessionId] {
            return existing
        }
        let pager = LargeImagePager()
        pagers[sessionId] = pager
        return pager
    }
}
