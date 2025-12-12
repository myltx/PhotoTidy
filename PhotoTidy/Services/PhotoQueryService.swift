import Foundation

/// 纯派生/过滤逻辑抽离，保证与现有 ViewModel 语义一致。
struct PhotoQueryService {
    func filteredItems(
        filter: CleanupFilterMode,
        from collection: [PhotoItem],
        isDeferredInTimeMachine: (PhotoItem) -> Bool,
        isInSelectedAlbum: (PhotoItem) -> Bool
    ) -> [PhotoItem] {
        let base = collection.filter {
            !$0.markedForDeletion
            && !isDeferredInTimeMachine($0)
            && isInSelectedAlbum($0)
        }
        switch filter {
        case .all:
            return base
        case .similar:
            return base.filter { $0.similarGroupId != nil }
        case .blurred:
            return base.filter { $0.isBlurredOrShaky }
        case .screenshots:
            return base.filter { $0.isScreenshot || $0.isDocumentLike }
        case .documents:
            return base.filter { $0.isDocumentLike }
        case .large:
            return base.filter { $0.isLargeFile }
        }
    }

    func monthItems(
        year: Int,
        month: Int,
        from items: [PhotoItem],
        isDeferredInTimeMachine: (PhotoItem) -> Bool,
        calendar: Calendar = .current
    ) -> [PhotoItem] {
        let filtered = items.filter { item in
            guard !item.markedForDeletion, let date = item.creationDate else { return false }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard comps.year == year && comps.month == month else { return false }
            return !isDeferredInTimeMachine(item)
        }
        return filtered.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func monthTotalCount(
        year: Int,
        month: Int,
        in items: [PhotoItem],
        calendar: Calendar = .current
    ) -> Int {
        items.reduce(0) { acc, item in
            guard let date = item.creationDate else { return acc }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return (comps.year == year && comps.month == month) ? acc + 1 : acc
        }
    }
}

