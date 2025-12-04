import Foundation

enum AnalysisTaskKind: String, Codable, Hashable {
    case similarity
    case blur
    case document
    case metadata
}

struct AnalysisTask: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: AnalysisTaskKind
    let assetId: String
    let scheduledAt: Date

    init(kind: AnalysisTaskKind, assetId: String) {
        self.id = UUID()
        self.kind = kind
        self.assetId = assetId
        self.scheduledAt = Date()
    }
}

actor AnalysisScheduler {
    private var tasks: [String: AnalysisTask] = [:]

    func schedule(kind: AnalysisTaskKind, assetIds: [String]) {
        for assetId in assetIds {
            let key = "\(kind.rawValue)-\(assetId)"
            guard tasks[key] == nil else { continue }
            tasks[key] = AnalysisTask(kind: kind, assetId: assetId)
        }
    }

    func drain(maxCount: Int? = nil) -> [AnalysisTask] {
        guard !tasks.isEmpty else { return [] }
        let ordered = tasks.values.sorted { $0.scheduledAt < $1.scheduledAt }
        let limit = maxCount ?? ordered.count
        let slice = Array(ordered.prefix(limit))
        for task in slice {
            tasks.removeValue(forKey: "\(task.kind.rawValue)-\(task.assetId)")
        }
        return slice
    }
}
